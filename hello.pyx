def say_hello_to(name):
    print("Hello %s!" % name)

cdef struct Test:
    int id


cdef void f(Test * t) nogil:
    t.id += 1

class A(object):

    def __init__(self):
        cdef Test t = Test()
        t.id = 10
        self.t = t

    def f2(self):
        cdef Test t
        t = self.t
        f(&t)
        print(t.id)