MKDIR_P = mkdir -p

all: xmlgen

xmlgen: xmlgen.d
	dmd -unittest xmlgen.d -ofxmlgen

gentestdata: xmlgen
	${MKDIR_P} testfiles	
	for i in 10 100 1000 10000 100000 ; do \
		for j in 0.0 0.1 0.2 0.5 0.7 1.0 ; do \
			echo "./xmlgen -r testfiles/type2_$${i}_$${j}.xml -e $$i -t 2 -u $$j"; \
			./xmlgen -r testfiles/type2_$${i}_$${j}.xml -e $$i -t 2 -u $$j ; \
		done \
	done
