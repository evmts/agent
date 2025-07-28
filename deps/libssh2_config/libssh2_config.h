/* Generated libssh2 config for Zig build */
#ifndef LIBSSH2_CONFIG_H
#define LIBSSH2_CONFIG_H

/* Crypto backend configuration */
#define LIBSSH2_MBEDTLS 1

/* Platform detection */
#ifdef _WIN32
    /* Windows configuration */
    #define HAVE_LIBCRYPT32 1
    #define HAVE_WINSOCK2_H 1
    #define HAVE_IOCTLSOCKET 1
    #define HAVE_SELECT 1
    #define LIBSSH2_DH_GEX_NEW 1
    #define _CRT_SECURE_NO_DEPRECATE 1
    
    #ifdef __MINGW32__
        #define HAVE_UNISTD_H 1
        #define HAVE_INTTYPES_H 1
        #define HAVE_SYS_TIME_H 1
        #define HAVE_GETTIMEOFDAY 1
    #endif
#else
    /* Unix-like systems (Linux, macOS, etc.) */
    #define HAVE_UNISTD_H 1
    #define HAVE_INTTYPES_H 1
    #define HAVE_STDLIB_H 1
    #define HAVE_SYS_SELECT_H 1
    #define HAVE_SYS_UIO_H 1
    #define HAVE_SYS_SOCKET_H 1
    #define HAVE_SYS_IOCTL_H 1
    #define HAVE_SYS_TIME_H 1
    #define HAVE_SYS_UN_H 1
    #define HAVE_LONGLONG 1
    #define HAVE_GETTIMEOFDAY 1
    #define HAVE_INET_ADDR 1
    #define HAVE_POLL 1
    #define HAVE_SELECT 1
    #define HAVE_SOCKET 1
    #define HAVE_STRTOLL 1
    #define HAVE_SNPRINTF 1
    #define HAVE_O_NONBLOCK 1
#endif

#endif /* LIBSSH2_CONFIG_H */