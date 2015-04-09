MKDIR_P = mkdir -p

all: xmlgen

xmlgen: xmlgen.d
	dmd -unittest xmlgen.d -ofxmlgen

gentestdata: xmlgen
	${MKDIR_P} testfiles	
	for i in 10 100 1000 10000 100000 ; do \
		for j in 0.0 0.1 0.2 0.5 0.7 1.0 ; do \
			echo "./xmlgen -r testfiles/type2_$${i}_$${j}.xml -e $$i -t 2 -u $$j --loglevel warning"; \
			./xmlgen -r testfiles/type2_$${i}_$${j}.xml -e $$i -t 2 -u $$j --loglevel warning; \
		done \
	done
	for i in 2 3 4 ; do \
		for j in 5 7 12 14; do \
			for k in 2 5 10 ; do \
				for l in 11 20 30 ; do \
					echo "./xmlgen -r testfiles/type0_$${i}_$${j}_$${k}_$${l}.xml -t 0 -b $$i -c $$j -f $$k -g $$l --loglevel warning"; \
					./xmlgen -r testfiles/type0_$${i}_$${j}_$${k}_$${l}.xml -t 0 -b $$i -c $$j -f $$k -g $$l --loglevel warning; \
					echo "./xmlgen -r testfiles/type1_$${i}_$${j}_$${k}_$${l}.xml -t 1 -b $$i -c $$j -f $$k -g $$l --loglevel warning"; \
					./xmlgen -r testfiles/type1_$${i}_$${j}_$${k}_$${l}.xml -t 1 -b $$i -c $$j -f $$k -g $$l --loglevel warning; \
				done \
			done \
		done \
	done
		

