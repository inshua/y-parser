# python setup.py build_ext --inplace

from distutils.core import setup
from Cython.Build import cythonize

setup(
  name = 'Hello world app',
  ext_modules = cythonize(["hello.pyx",
                           "t6.pyx",
                           "y_parser.pyx"
                           ]),
)
