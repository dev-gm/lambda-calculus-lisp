#include <error_handling.h>

void exit_if(bool cond, int errno, const char *fmt, ...) {
	if (cond) {
		va_list args;
		va_start(args, fmt);
		vfprintf(stderr, fmt, args);
		va_end(args);
		fputs("\n", stderr);
		exit(errno);
	}
}
