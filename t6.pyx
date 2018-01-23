import time

# 如指定 nogil 可提速到 0.000
cdef void f(unsigned char s) nogil:
    pass

def it(unsigned char * arr, int length) -> None:    # unsigned 0.064 bytearray 0.067
    cdef unsigned char c = 0
    cdef int i = 0
    cdef int count = 0
    with nogil:
        for i in range(length):         # 0.07  0.067
        # for i from 0 <= i < length:   # 0.095
            c = arr[i]
            f(c)
            count += c
    # print(count)


cdef void f2(Py_UCS4 s):
    pass


def it_s(unicode s) -> None:    #0.0000
    cdef int count = 0
    for c in s:
        # if uchar == u'A'
        f2(c)
        count += 1
    print(count)

