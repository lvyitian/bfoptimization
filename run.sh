#!/bin/bash

set -e

OPTS="contract clearloop copyloop multiloop offsetops scanloop all"
PROGS=$(ls progs | egrep '\.b$')

# return the average runtime of 10 runs. ignores the slowest of the 10.
avgruntime() {
    > tmp.dat
    TIMEFORMAT="%R"
    for i in $(seq 10); do
	{ time $1 < $2 > $3 2> /dev/null ; } 2>>tmp.dat
    done
    echo "scale=4; ($(sort tmp.dat | head -n-1 | tr '\n' '+') 0) / 9" | bc
}

# measure runtime for all optimizations on all programs
for optimization in $OPTS; do

    for program in $PROGS; do

	if test -f $optimization.dat && grep $program $optimization.dat >/dev/null; then
	    continue
	fi

	# make sure we have runtime without optimizations
	if [ ! -f $program.none.dat -o ! -f progs/$program.out ]; then
	    echo "$program without optimization"
	    python optimizr.py none <progs/$program > tmp.c
	    gcc -Wno-int-to-pointer-cast -O0 tmp.c -o tmp
	    avgruntime ./tmp progs/$program.in tmp.out > $program.none.dat
	    if ! cmp tmp.out progs/$program.out; then
		echo "EPIC MEGA FAIL"
		exit 1
	    fi
	    rm tmp.c tmp
	fi

	# run with opt and add improvement to data file
	echo "$program with $optimization"
	python optimizr.py $optimization <progs/$program > tmp.c
	gcc -Wno-int-to-pointer-cast -O0 tmp.c -o tmp
	rm tmp.c
	echo -ne "$program\t" >> $optimization.dat
	echo -ne "$(avgruntime ./tmp progs/$program.in tmp.out)" >> $optimization.dat
	echo -e "\t$(<$program.none.dat)" >> $optimization.dat

	# verify that the output was correct
	if ! cmp tmp.out progs/$program.out; then
	    echo "EPIC MEGA FAIL"
	    exit 1
	fi
    done

    # gnuplot!
    echo "plotting $optimization.p"
    cat > $optimization.p <<EOF
set terminal png
set output "$optimization.png"
set title "$optimization optimization"
set auto x
set yrange [0:1]
set ytic 0.1
set style data histogram
set style histogram cluster gap 1
set style fill solid 1.0 noborder
set grid y
set xtic rotate by -45 scale 0
set boxwidth 0.9
set ylabel "runtime relative to unoptimized version"
plot '$optimization.dat' using (\$2 / \$3):xticlabels(1) notitle
EOF

   gnuplot $optimization.p

done

# plot offsetops and reorder side by side
if test -f offsetops.dat && test -f reorder.dat; then
    echo "plotting offsetops vs reorder"
    > offset_reorder.dat
    for program in $PROGS; do
	echo -ne "$program\t" >> offset_reorder.dat
	echo -ne "$(grep $program offsetops.dat | cut -f2)\t" >> offset_reorder.dat
	echo -ne "$(grep $program reorder.dat | cut -f2,3)\n" >> offset_reorder.dat
    done

    cat > offset_reorder.p <<EOF
set terminal png
set output "offset_reorder.png"
set title "offsetsops and reorder optimization speedup"
set key inside top left box
set auto x
set yrange [0:1]
set style data histogram
set style histogram cluster gap 1
set style fill solid 1.0 noborder
set grid y
set xtic rotate by -45 scale 0
set boxwidth 0.9
set ylabel "runtime relative to  unoptimized version"
plot 'offset_reorder.dat' using (\$2 / \$4):xticlabel(1) title 'offsets', \
     '' u (\$3 / \$4) title 'offsets and reorder'
EOF

    gnuplot offset_reorder.p
fi

# plot actual runtimes without optimization
echo "plotting runtimes"
> runtime.dat
for program in $PROGS; do
    echo -e "$program\t$(<$program.none.dat)" >> runtime.dat
done

cat > runtime.p <<EOF
set terminal png
set output "runtime.png"
set title "runtime without optimizations"
set auto x
set yrange [0:*]
set style data histogram
set style histogram cluster gap 1
set style fill solid 1.0 noborder
set grid y
set xtic rotate by -45 scale 0
set boxwidth 0.9
set ylabel "seconds"
plot 'runtime.dat' using 2:xticlabel(1) notitle
EOF

gnuplot runtime.p


# plot actual runtimes with and without optimization
> runtime2.dat
for program in $PROGS; do
    echo -ne "$program\t$(<$program.none.dat)\t" >> runtime2.dat
    grep $program all.dat | awk '{print $2}' >> runtime2.dat
done

cat > runtime2.p <<EOF
set terminal png
set output "runtime2.png"
set title "runtime with and without optimizations"
set key inside top left box
set auto x
set yrange [0:*]
set style data histogram
set style histogram cluster gap 1
set style fill solid 1.0 noborder
set grid y
set xtic rotate by -45 scale 0
set boxwidth 0.9
set ylabel "seconds"
plot 'runtime2.dat' using 2:xticlabel(1) title 'no optimization', \
     '' u 3 title 'all optimizations'
EOF

gnuplot runtime2.p

# run the analyzer script on the programs and gather some stats
> codestats_contract.dat
for program in $PROGS; do
    echo -ne "$program\t" >> codestats_contract.dat
    python analyze.py < progs/$program | grep contract | awk '{print $4}' >> codestats_contract.dat

done

cat > codestats_contract.p <<EOF
set terminal png
set output "codestats_contract.png"
set title "ratio of contractable instructions"
set key inside top left box
set auto x
set yrange [0:1]
set style data histogram
set style histogram cluster gap 1
set style fill solid 1.0 noborder
set grid y
set xtic rotate by -45 scale 0
set boxwidth 0.9
set ylabel ""
plot 'codestats_contract.dat' using 2:xticlabel(1) title ''
EOF

gnuplot codestats_contract.p
