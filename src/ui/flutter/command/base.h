#ifdef _WIN32
  #include <windows.h>
#else
  #include <pthread.h>
  #include <stdlib.h>
  #include <unistd.h>
#endif
#include <string.h>

#ifndef BASE2_H
#define BASE2_H

#ifdef _WIN32

inline void Idle(void) {
  Sleep(1);
}

#else

inline void Idle(void) {
  usleep(1000);
}
#endif

#endif
