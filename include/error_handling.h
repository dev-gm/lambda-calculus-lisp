#ifndef ERROR_HANDLING_H

#define ERROR_HANDLING_H

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <stdarg.h>

void exit_if(bool cond, int errno, const char *fmt, ...);

#define exit_if_null(val, errno, fmt, ...) exit_if((val)==NULL, errno, fmt, __VA_ARGS__)
#define exit_if_nonzero(val, errno, fmt, ...) exit_if((val)!=0, errno, fmt, __VA_ARGS__)


#endif

