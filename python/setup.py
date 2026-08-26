from setuptools import setup, find_packages

setup(
    name='selenium-core',
    version='0.1.0',
    description='Selenium WebDriver for Python — a thin ctypes wrapper over the '
                'shared pure-Aether WebDriver core (libselenium_core.so)',
    author='Paul Hammant',
    author_email='paul@hammant.org',
    url='https://github.com/SeleniumHQ/selenium',
    license='Apache-2.0',
    python_requires='>=3.9',
    packages=find_packages(exclude=['test', 'test.*']),
    # Ship the prebuilt native engine inside the package so a naive
    # `pip install` works with no separate .so to locate.
    package_data={'selenium_core': ['native/*.so', 'native/*.dylib', 'native/*.dll']},
    include_package_data=True,
    # No runtime dependencies: the binding uses only the stdlib (ctypes + json).
    install_requires=[],
    extras_require={'dev': ['pytest']},
)
