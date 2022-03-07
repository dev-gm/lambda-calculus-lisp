CC=clang
IDIR=./include/
CFLAGS=-Wall -Wextra -Wpedantic -I$(IDIR) -g
OUTFILE=./compiler

SDIR=./src
ODIR=./obj
LDIR=./lib

LIBS=

ARGS=test

FILES=error_handling parser main

$(ODIR)/%.o: $(SDIR)/%.c
	$(CC) -c -o $@ $< $(CFLAGS)

$(OUTFILE): $(patsubst %,$(ODIR)/%.o,$(FILES))
	$(CC) -o $@ $^ $(CFLAGS) $(LIBS)

.PHONY: run test debug clean

run:
	$(OUTFILE) $(ARGS)

test:
	make clean && make && make run

debug:
	make clean && make && gdb --args $(OUTFILE) $(ARGS)

clean:
	rm $(OUTFILE) -f

