#!/usr/bin/env python3
"""check_auth.py - Icinga/Nagios check: can we actually log in to FTP/IMAP/POP3/SMTP?

This version reports what went wrong:

    CRITICAL - SMTPs auth rejected by server (535)       <- password really is wrong
    CRITICAL - SMTPs timed out after 10s (connect)       <- server is slow/overloaded
    CRITICAL - SMTPs connection refused                  <- daemon is down
    CRITICAL - SMTPs TLS handshake failed: ...           <- cert/protocol problem
    UNKNOWN  - cannot read /root/pass.yaml               <- our own config, not the service

It also closes TLS properly. Python's ssl module only emits close_notify on an
explicit unwrap(); smtplib/imaplib/poplib all go straight to socket.close(),
which is why exim (GnuTLS) logs

    TLS error on connection from <poller> (recv): The TLS connection was non-properly terminated.

every time this check runs against a TLS port. Sending close_notify first stops
that log noise. See _tls_close().

Exit codes follow the plugin API: 0 OK, 1 WARNING, 2 CRITICAL, 3 UNKNOWN.
"""

import argparse
import os
import socket
import ssl
import stat
import sys
import time

import yaml

OK, WARNING, CRITICAL, UNKNOWN = 0, 1, 2, 3

DEFAULT_PASS_FILE = '/root/pass.yaml'

# Added in Python 3.7; None on anything older, where a bad certificate simply
# surfaces as a plain ssl.SSLError instead.
_SSL_CERT_ERROR = getattr(ssl, 'SSLCertVerificationError', None)

# service -> (default port, which credential pair it uses)
SERVICES = {
    'ftp':    (21,  'f'),
    'ftps':   (21,  'f'),
    'imap':   (143, 'e'),
    'imaps':  (993, 'e'),
    'pop3':   (110, 'e'),
    'pop3s':  (995, 'e'),
    'smtp':   (25,  'e'),
    'smtps':  (465, 'e'),
}


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------

class Redactor:
    """Keeps credentials out of check output.

    Server error strings are echoed into the Icinga status, and some daemons
    quote the login (and, misconfigured, more) back at you. Icinga status text
    is stored and often forwarded, so scrub the secrets before they get there.
    """

    def __init__(self):
        self._secrets = []

    def add(self, value):
        if isinstance(value, str) and len(value) >= 4:
            self._secrets.append(value)

    def __call__(self, text: str) -> str:
        for secret in self._secrets:
            text = text.replace(secret, '***')
        return text


redact = Redactor()


def _tls_close(sock) -> None:
    """Send TLS close_notify, if this is a TLS socket.

    Without it the peer sees the TCP FIN arrive mid-session and logs a
    premature-termination error (GNUTLS_E_PREMATURE_TERMINATION on exim).
    Best effort: a half-dead connection raises here and that is fine, we are
    on our way out anyway.
    """
    if isinstance(sock, ssl.SSLSocket):
        try:
            sock.unwrap()
        except (OSError, ValueError):
            pass


def _short(exc: BaseException) -> str:
    """One-line, redacted rendering of an exception."""
    text = str(exc).strip().replace('\n', ' ').replace('\r', ' ')
    if not text:
        text = type(exc).__name__
    if len(text) > 180:
        text = text[:177] + '...'
    return redact(text)


def classify(exc: BaseException, label: str, phase: str, timeout: float):
    """Map a transport-level exception to (exit code, message).

    Protocol-specific auth errors are handled by each check function before
    this is reached; everything here is the shared network/TLS layer.
    """
    if isinstance(exc, socket.gaierror):
        return CRITICAL, f'{label} DNS lookup failed: {_short(exc)}'
    # socket.timeout is an alias of TimeoutError on Python 3.10+
    if isinstance(exc, (socket.timeout, TimeoutError)):
        return CRITICAL, f'{label} timed out after {timeout:g}s ({phase})'
    if isinstance(exc, ConnectionRefusedError):
        return CRITICAL, f'{label} connection refused ({phase})'
    if isinstance(exc, ConnectionResetError):
        return CRITICAL, f'{label} connection reset by peer ({phase})'
    if _SSL_CERT_ERROR is not None and isinstance(exc, _SSL_CERT_ERROR):
        return CRITICAL, f'{label} certificate verification failed: {_short(exc)}'
    if isinstance(exc, ssl.SSLError):
        return CRITICAL, f'{label} TLS handshake failed: {_short(exc)}'
    if isinstance(exc, OSError):
        return CRITICAL, f'{label} network error ({phase}): {_short(exc)}'
    return CRITICAL, f'{label} failed ({phase}): {type(exc).__name__}: {_short(exc)}'


# --------------------------------------------------------------------------
# per-service checks
# --------------------------------------------------------------------------
#
# Each returns (exit_code, message). Each separates three phases so the message
# can say *where* it broke: connect, auth, quit. A failure during quit is not
# worth alerting on - we already proved the login works - so it degrades to
# WARNING rather than CRITICAL.

def check_ftp(host, port, user, password, timeout, tls, **_):
    from ftplib import FTP, FTP_TLS, error_perm, error_temp

    label = 'FTPs' if tls else 'FTP'
    conn = None
    try:
        conn = (FTP_TLS if tls else FTP)()
        conn.connect(host, port)
    except Exception as exc:
        return classify(exc, label, 'connect', timeout)

    try:
        conn.login(user=user, passwd=password)
        if tls:
            # Without this the data connection stays cleartext. We open none,
            # but asking for it proves the server honours PROT.
            conn.prot_p()
    except error_perm as exc:
        _abandon(conn)
        return CRITICAL, f'{label} auth rejected by server: {_short(exc)}'
    except error_temp as exc:
        _abandon(conn)
        return CRITICAL, f'{label} temporary server error: {_short(exc)}'
    except Exception as exc:
        _abandon(conn)
        return classify(exc, label, 'auth', timeout)

    try:
        conn.voidcmd('QUIT')
        _tls_close(conn.sock)
        conn.close()
    except Exception as exc:
        _abandon(conn)
        return WARNING, f'{label} login OK but QUIT failed: {_short(exc)}'

    return OK, f'{label} login successful'


def check_imap(host, port, user, password, timeout, tls, starttls, **_):
    from imaplib import IMAP4, IMAP4_SSL

    label = 'IMAPs' if tls else 'IMAP'
    conn = None
    try:
        if tls:
            conn = IMAP4_SSL(host, port)
        else:
            conn = IMAP4(host, port)
            if starttls:
                conn.starttls()
                label = 'IMAP+STARTTLS'
    except Exception as exc:
        return classify(exc, label, 'connect', timeout)

    try:
        conn.login(user, password)
    except IMAP4.error as exc:
        # imaplib raises IMAP4.error for a plain "NO" as well as for protocol
        # faults; the server text is the only thing separating them.
        _abandon(conn)
        return CRITICAL, f'{label} auth rejected by server: {_short(exc)}'
    except Exception as exc:
        _abandon(conn)
        return classify(exc, label, 'auth', timeout)

    try:
        # Plain logout(), nothing clever. It sets state='LOGOUT' before issuing
        # the command and swallows the abort that the server's untagged
        # "* BYE Logging out" raises inside _command_complete. Driving
        # _simple_command('LOGOUT') by hand to slip a close_notify in first
        # gets that abort thrown in our face instead, which reported WARNING on
        # every successful check.
        #
        # So IMAP is the one protocol here that cannot send close_notify:
        # logout() closes the socket itself. Dovecot notes the abrupt close far
        # more quietly than exim does, and a false WARNING every run is much
        # worse than a log line.
        conn.logout()
    except Exception as exc:
        _abandon(conn)
        return WARNING, f'{label} login OK but LOGOUT failed: {_short(exc)}'

    return OK, f'{label} login successful'


def check_pop3(host, port, user, password, timeout, tls, starttls, **_):
    from poplib import POP3, POP3_SSL, error_proto

    label = 'POP3s' if tls else 'POP3'
    conn = None
    try:
        if tls:
            conn = POP3_SSL(host, port)
        else:
            conn = POP3(host, port)
            if starttls:
                conn.stls()
                label = 'POP3+STARTTLS'
    except Exception as exc:
        return classify(exc, label, 'connect', timeout)

    try:
        conn.user(user)
        conn.pass_(password)
    except error_proto as exc:
        _abandon(conn)
        return CRITICAL, f'{label} auth rejected by server: {_short(exc)}'
    except Exception as exc:
        _abandon(conn)
        return classify(exc, label, 'auth', timeout)

    try:
        # quit() closes the socket directly, so send close_notify first.
        if hasattr(conn, '_shortcmd'):
            conn._shortcmd('QUIT')
            _tls_close(conn.sock)
            conn.close()
        else:
            conn.quit()
    except Exception as exc:
        _abandon(conn)
        return WARNING, f'{label} login OK but QUIT failed: {_short(exc)}'

    return OK, f'{label} login successful'


def check_smtp(host, port, user, password, timeout, tls, starttls, **_):
    from smtplib import (SMTP, SMTP_SSL, SMTPAuthenticationError,
                         SMTPNotSupportedError, SMTPServerDisconnected,
                         SMTPResponseException)

    label = 'SMTPs' if tls else 'SMTP'
    conn = None
    try:
        if tls:
            conn = SMTP_SSL(host, port)
        else:
            conn = SMTP(host, port)
            conn.ehlo()
            if starttls:
                conn.starttls()
                conn.ehlo()
                label = 'SMTP+STARTTLS'
    except Exception as exc:
        return classify(exc, label, 'connect', timeout)

    try:
        conn.login(user, password)
    except SMTPAuthenticationError as exc:
        _abandon(conn)
        return CRITICAL, (f'{label} auth rejected by server ({exc.smtp_code}): '
                          f'{redact(_decode(exc.smtp_error))}')
    except SMTPNotSupportedError as exc:
        # The usual cause on port 25: the server advertises no AUTH until the
        # session is encrypted. That is a check misconfiguration, not an outage,
        # so say so instead of crying "password wrong" forever.
        _abandon(conn)
        return CRITICAL, (f'{label} server does not offer AUTH on this port '
                          f'({_short(exc)}) - try --starttls or the TLS port')
    except SMTPServerDisconnected as exc:
        _abandon(conn)
        return CRITICAL, f'{label} server disconnected during auth: {_short(exc)}'
    except SMTPResponseException as exc:
        _abandon(conn)
        return CRITICAL, (f'{label} refused auth ({exc.smtp_code}): '
                          f'{redact(_decode(exc.smtp_error))}')
    except Exception as exc:
        _abandon(conn)
        return classify(exc, label, 'auth', timeout)

    try:
        conn.docmd('QUIT')
        _tls_close(conn.sock)
        conn.close()
    except Exception as exc:
        _abandon(conn)
        return WARNING, f'{label} login OK but QUIT failed: {_short(exc)}'

    return OK, f'{label} login successful'


def _decode(value) -> str:
    if isinstance(value, bytes):
        value = value.decode('utf-8', 'replace')
    return str(value).strip().replace('\n', ' ')


def _abandon(conn) -> None:
    """Drop a connection we are giving up on, as cleanly as we still can."""
    if conn is None:
        return
    try:
        _tls_close(getattr(conn, 'sock', None))
    except Exception:
        pass
    for closer in ('close', 'quit', 'logout'):
        method = getattr(conn, closer, None)
        if callable(method):
            try:
                method()
                return
            except Exception:
                continue


HANDLERS = {
    'ftp':   (check_ftp,   {'tls': False, 'starttls': False}),
    'ftps':  (check_ftp,   {'tls': True,  'starttls': False}),
    'imap':  (check_imap,  {'tls': False, 'starttls': False}),
    'imaps': (check_imap,  {'tls': True,  'starttls': False}),
    'pop3':  (check_pop3,  {'tls': False, 'starttls': False}),
    'pop3s': (check_pop3,  {'tls': True,  'starttls': False}),
    'smtp':  (check_smtp,  {'tls': False, 'starttls': False}),
    'smtps': (check_smtp,  {'tls': True,  'starttls': False}),
}


# --------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------

def load_credentials(path: str):
    """Returns (data, notes). Config problems raise, they are not CRITICAL."""
    notes = []
    try:
        st = os.stat(path)
    except OSError as exc:
        raise RuntimeError(f'cannot stat {path}: {exc.strerror}')

    if st.st_mode & (stat.S_IRGRP | stat.S_IROTH):
        notes.append(f'{path} is readable beyond its owner '
                     f'(mode {stat.filemode(st.st_mode)}); it holds live '
                     f'credentials and should be 0600 root:root')

    try:
        with open(path, 'r', encoding='utf-8') as handle:
            data = yaml.load(handle, Loader=yaml.BaseLoader)
    except OSError as exc:
        raise RuntimeError(f'cannot read {path}: {exc.strerror}')
    except yaml.YAMLError as exc:
        raise RuntimeError(f'{path} is not valid YAML: {exc}')

    if not isinstance(data, dict):
        raise RuntimeError(f'{path} did not parse to a mapping')
    return data, notes


def main() -> int:
    parser = argparse.ArgumentParser(
        description='Check that a mail/FTP service accepts a known login.')
    parser.add_argument('--service', '-s', required=True, choices=sorted(SERVICES),
                        help='service to test')
    parser.add_argument('--hostname', '-H', default='127.0.0.1')
    parser.add_argument('--port', '-p', type=int, default=None,
                        help='override the default port for the service')
    parser.add_argument('--timeout', '-t', type=float, default=10.0,
                        help='per-operation timeout in seconds (default 10)')
    parser.add_argument('--starttls', action='store_true',
                        help='issue STARTTLS/STLS on the cleartext variants')
    parser.add_argument('--pass-file', default=DEFAULT_PASS_FILE)
    args = parser.parse_args()

    try:
        creds, notes = load_credentials(args.pass_file)
    except RuntimeError as exc:
        print(f'UNKNOWN - {exc}')
        return UNKNOWN

    default_port, prefix = SERVICES[args.service]
    user = creds.get(f'{prefix}_user')
    password = creds.get(f'{prefix}_pass')
    if not user or not password:
        print(f'UNKNOWN - {args.pass_file} has no {prefix}_user/{prefix}_pass '
              f'entry for service {args.service}')
        return UNKNOWN

    redact.add(password)

    # Every timeout in this check comes from here, exactly as the original
    # script did it. The stdlib clients grew their own timeout= arguments at
    # different versions (imaplib only at 3.9), so passing it per-constructor
    # would tie this check to an interpreter newer than the one it runs on.
    # A global default bounds every socket operation on any version.
    socket.setdefaulttimeout(args.timeout)

    handler, flags = HANDLERS[args.service]
    port = args.port or default_port

    started = time.monotonic()
    try:
        code, message = handler(
            host=args.hostname,
            port=port,
            user=user,
            password=password,
            timeout=args.timeout,
            starttls=args.starttls or flags['starttls'],
            tls=flags['tls'],
        )
    except Exception as exc:  # a bug in this script, not a service failure
        print(f'UNKNOWN - check_auth internal error: '
              f'{type(exc).__name__}: {_short(exc)}')
        return UNKNOWN
    elapsed = time.monotonic() - started

    state = {OK: 'OK', WARNING: 'WARNING', CRITICAL: 'CRITICAL'}[code]
    print(f'{state} - {message} ({args.hostname}:{port}) '
          f'| time={elapsed:.3f}s;;;0')
    for note in notes:
        print(f'note: {note}')
    return code


if __name__ == '__main__':
    sys.exit(main())
