#!/bin/bash
#pokud jsou zadany oba parametry tak hlida . Jinak jen sbira data. Prvni warning a druhy error. Nastavuje se v procentech pozadovany minimalni stav volne pameti. Volna pamet se pocita vcetne cache

TOTAL=`cat /proc/meminfo | grep MemTotal |  awk '{ print $2 }' `

TOTAL=$(( $TOTAL/1024 ));


FREE=`cat /proc/meminfo | grep MemFree |  awk '{ print $2 }'  `
FREE=$(( $FREE/1024 ));

CACHED=`cat /proc/meminfo | grep "Cached:" | grep -v Swap | awk '{ print $2 }' `
CACHED=$(( $CACHED/1024 ));

BUFFERS=`cat /proc/meminfo | grep Buffers |  awk '{ print $2 }' `
BUFFERS=$(( $BUFFERS/1024 ));
USED=$(( $TOTAL - $FREE - $CACHED - $BUFFERS ));

FREEPLUSCACHE=$(( $FREE + $CACHED + $BUFFERS));

FREEPERCENT=$(( 100 * $FREEPLUSCACHE / $TOTAL ))


if [ $# = 2 ]; then
	if [ $FREEPERCENT -gt $1 ] && [ $FREEPERCENT -gt $2 ]; then
		echo -n "OK - Mem free ${FREEPLUSCACHE}MB (${FREEPERCENT}%)| ";
		EX=0;
	elif [ $FREEPERCENT -lt $1 ] && [ $FREEPERCENT -gt $2 ]; then
		echo -n "WARNING - Mem free ${FREEPLUSCACHE}MB (${FREEPERCENT}%)| "
		EX=1;
	else
                echo -n "CRITICAL - Mem free ${FREEPLUSCACHE}MB (${FREEPERCENT}%)| "
		EX=2;
	fi

else
	echo -n "OK Mem free ${FREEPLUSCACHE}MB (${FREEPERCENT}%)| "
	EX=0;

fi;


awk -v hz=${HZ:-100} '/^cpu / { printf "user=%.0f; nice=%.0f; system=%.0f; idle=%.0f; iowait=%.0f; irq=%.0f; softirq=%.0f; steal=%.0f; ", $2*100/hz, $3*100/hz, $4*100/hz, $5*100/hz, $6*100/hz, $7*100/hz, $8*100/hz, $9*100/hz }' < /proc/stat
#awk '/pswpin/ { print "swap_in= " $2 } /pswpout/ { print "swap_out= " $2 }' < /proc/vmstat
SWAP=`awk '/pswpin/ { print "swap_in="$2 } /pswpout/ { print "; swap_out="$2 }' < /proc/vmstat | sed ':a;N;$!ba;s/\n//g'`

echo -n $SWAP | sed ':a;N;$!ba;s/\n//g';



echo -n  "; mem_total=$TOTAL;;;;$TOTAL mem_used=$USED;;;;$TOTAL mem_free=$FREE;;;;$TOTAL mem_cached=$CACHED;;;;$TOTAL mem_buffers=$BUFFERS;;;$TOTAL"

IFS=$"\n"
stats=`cat /proc/diskstats`
IFS=" ";

while IFS= read -r part; do
	if [[ "$part" =~ ^/dev/mapper/ ]]; then
		part=$(sudo dmsetup ls | grep "$(basename "$part	")" | sed -r 's|.*([0-9])\)$|dm-\1|g')
	else
		part=$(basename "$part")
	fi

	READIO=`echo $stats | grep "$part " | awk '{ print $4 }' `
	[ -z "$READIO" ] && continue
	WRITEIO=`echo $stats | grep "$part " | awk '{ print $8 }' `
	READS=`echo $stats | grep "$part " | awk '{ print $6 }' `
	READ=$(($READS*512));
	WRITES=`echo $stats | grep "$part " | awk '{ print $10}' `
	WRITE=$(($WRITES*512));
	echo -n "; ${part}_readio=${READIO}; ${part}_writeio=${WRITEIO}; ${part}_read=${READ}; ${part}_write=${WRITE}";

done <<< "$(awk '$3 ~ /^(ext3|ext2|ext4|xfs|zfs)/ {print $1}' /etc/mtab | sort | uniq)"


exit $EX;
