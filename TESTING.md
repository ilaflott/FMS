# Unit Testing

FMS includes a suite of MPI unit tests for most subdirectories and modules that make up the library.

It consists of programs in the test_fms/ directory, with shell scripts to handle directory set up and input files.
test_lib.sh.in and tap-driver.sh provide additional helper functions used in the scripts and manage output.

The unit tests can be run either through the autotools build system, or through cmake via ctest.
The different build systems will run the exact same scripts and executables, but there are some differences in the commands used to start the testing.

## Autotools Unit Testing

### Running the Tests

1. Configure and build the code with autotools
```
mkdir build # create a build directory in FMS
cd build
autoreconf -if ../configure.ac
../configure <configure options>
make
```

2. Build and run suite
```
make check
```
This will compile any code not already compiled and then proceed to run the test scripts.

If a test fails, `make check` will stop running the rest of the unit tests once it is done with the current subdirectory.

To instead run all of the tests regardless of failures, the `-k` option can be given:
```
make check -k
```

### Debugging Output and Test Options for Autotools

Setting the environment variable TEST_VERBOSE will direct output to stdout as the test runs, while setting VERBOSE will only output on failure.
Logs are created for each test as well, with the name \<test script name\>.log in its corresponding test_fms/ directory.

To run an individual test:
```
make check -C test_fms/<test directory> TESTS=<test script name>
```

SKIP_TESTS can be set to in order to skip specific tests in a script. It uses the script name and test number, and takes ranges as well:
```
SKIP_TESTS="test_name.4 test_name.[1-3]"
```

Some options that effect the test suite can be set by passing options to the ./configure script that creates the makefiles
for the build system:

-    `--enable-code-coverage` allows for compilation with flags for coverage information.
     If enabled a coverage report can be generated with `make check-code-coverage`
-    `--enable-test-input=/path/to/input` turns on test scripts that require input netcdf files (interpolator, xgrid, data_override).
     This option is mainly used internally and in automated testing since we do not host the input data publicly.
-    `--with-yaml` compile with yaml input and enable its associated tests

## CMake Unit Testing

### Running the tests

1. Configure and build the code and tests with cmake
```
mkdir build
cd build
cmake <Any cmake options such as -DWITH_YAML=on> ..
make
```
2. Run the tests with ctest
```
ctest
```
Alternatively, the generated makefile can be used as well:
```
make test
```
### Debugging and Test Options for CMake

To rerun failed tests with debug output from a previous failed ctest command:
```
ctest --rerun-failed --verbose
```
All tests are labeled with the subdirectory they are in in the `test_fms` directory.
To run tests for a specific area of the code, such as the mpp modules:
```
ctest -L mpp
```
To run specific tests matching the given regex:
```
ctest -R <regex>
```

For more testing options with ctest, you can look to the [ctest documentation](https://cmake.org/cmake/help/latest/manual/ctest.1.html).

## Directional Tripolar Folds and MOM6 Index Rotation

The directional-fold regressions run with:

```sh
make -C <build>/test_fms/mpp check \
  TESTS='test_mpp_update_domains.sh test_mpp_domains2.sh test_mpp_update_domains_ad.sh'
```

The bounds/FPE-checked local run passes 23 cases, with one pre-existing skip.
Coverage includes entirely negative tangential origins and independent nonzero
caller-owned South/West vector faces. The latter checks ownership, reflection
signs, B-grid poles, and adjacent ghosts without using another update routine
as its reference.

MOM6 integration comparisons require care: successful execution of
`ROTATE_INDEX=True`, `INDEX_TURNS=0,1,2,3` does not establish that physical fields
agree. Investigation at MOM6 revision
`d68539668b7014bc284a1d1a14c4c415a84c79ce` identified two MOM6 rotation problems.
No MOM6 checkout is modified by this FMS work.

### Fold Direction Rotates Opposite to the Arrays

In
[`clone_MD_to_MD`](https://github.com/NOAA-GFDL/MOM6/blob/d68539668b7014bc284a1d1a14c4c415a84c79ce/config_src/infra/FMS2/MOM_domain_infra.F90#L1593-L1606),
one quarter turn maps a North fold to East. However,
[`rotate_array_real_2d`](https://github.com/NOAA-GFDL/MOM6/blob/d68539668b7014bc284a1d1a14c4c415a84c79ce/src/framework/MOM_array_transform.F90#L97-L114)
transposes the array and reverses its first axis, moving the original North
edge to West. The three-quarter-turn mappings are likewise reversed.
Consequently, a halo update can treat the physically closed side as folded.

**Suggested MOM6 solution:** make domain cloning use the same rotation sense
as the arrays. For one quarter turn, map North to West, South to East,
East to North, and West to South; use the inverse mapping for three turns.
Check both infrastructure implementations and add an edge-mapping regression.

An experiment correcting only this mapping in an isolated source snapshot
makes all four symmetric-storage integrations agree exactly in final `h`, `u`,
and `v`: every maximum absolute difference is zero. This is diagnostic evidence,
not a MOM6 production change included in this repository.

### Compact Staggered Faces Need Different Reflection Indices

Nonsymmetric storage gives tracer and face arrays the same shape. MOM6's
generic array reversal therefore treats their indices identically, despite
the NE faces being at `(i+1/2,j)` and `(i,j+1/2)`.
For tracer indices `1:nx,1:ny`, a half turn maps a tracer's first index to
`nx+1-i`, but an east face's first index to `nx-i`. A north face similarly
needs `ny-j` rather than `ny+1-j` in the second direction.

A standalone call to MOM6's existing `rotate_vector`, without linking or
calling FMS, reproduces the misregistration. With `nx=6`, `ny=4`, arrays indexed
`0:nx+1,0:ny+1`, and tags `u(i,j)=100*i+j`, `v(i,j)=10000+100*i+j`,
the half-turned values at `(2,2)` are:

| Component | Actual | Physical NE-face expectation |
| --- | ---: | ---: |
| `u` | -503 | -403 |
| `v` | -10503 | -10502 |

**Suggested MOM6 solution:** make index rotation aware of grid position and
storage symmetry, and use it consistently for geometry, initial conditions,
and restart/output transformations. Preserve valid lower face endpoints and
explicitly account for the available halo bounds. Verify with nonzero
staggered fields on rectangular grids; do not compensate with fitted output
translations or looser comparison tolerances.

After the topology-only experiment, all four nonsymmetric runs finish but
still fail numerical equivalence. The generated spherical tripolar case has
24 by 16 cells, two layers, a flat 2000 m bottom, and a 7200 s integration.
Comparisons retain `rtol=1e-10`, thickness `atol=1e-8 m`, and velocity
`atol=1e-11 m/s`. Compact-storage MOM6 rotation acceptance remains unresolved;
passing FMS unit tests or the symmetric experiment does not remove that limit.
