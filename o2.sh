package: O2
version: "%(tag_basename)s"
tag: "daily-20250711-0000"
requires:
  - abseil
  - arrow
  - FairRoot
  - Vc
  - HepMC3
  - libInfoLogger
  - Common-O2
  - Configuration
  - Monitoring
  - ms_gsl
  - FairMQ
  - curl
  - MCStepLogger
  - fmt
  - "openmp:(?!osx.*)"
  - DebugGUI
  - JAliEn-ROOT
  - fastjet
  - libuv
  - libjalienO2
  - cgal
  - "VecGeom:(?!osx.*)"
  - FFTW3
  - ONNXRuntime
  - nlohmann_json
  - MLModels
  - RapidJSON
  - bookkeeping-api
  - AliEn-CAs
  - gpu-system
build_requires:
  - abseil
  - GMP
  - MPFR
  - googlebenchmark
  - O2-customization
  - Clang:(?!osx*)
  - ITSResponse
source: https://github.com/AliceO2Group/AliceO2
env:
  VMCWORKDIR: "$O2_ROOT/share"
prepend_path:
  ROOT_INCLUDE_PATH: "$O2_ROOT/include:$O2_ROOT/include/GPU"
incremental_recipe: |
  unset DYLD_LIBRARY_PATH
  if [[ ! $CMAKE_GENERATOR && $DISABLE_NINJA != 1 && $DEVEL_SOURCES != $SOURCEDIR ]]; then
    NINJA_BIN=ninja-build
    type "$NINJA_BIN" &> /dev/null || NINJA_BIN=ninja
    type "$NINJA_BIN" &> /dev/null || NINJA_BIN=
    [[ $NINJA_BIN ]] && CMAKE_GENERATOR=Ninja || true
    unset NINJA_BIN
  fi
  if [ "X$CMAKE_GENERATOR" = XNinja ]; then
    # Find the old binary byproducts
    mkdir -p stage/{bin,lib,tests}
    find stage/{bin,lib,tests} -type f > old.txt
    # Find new targets
    ninja -t targets all  | grep stage | cut -f1 -d: > new.txt
    # Delete all those which are found twice (i.e. which are in old.txt only)
    # FIXME: this breaks some corner cases, apparently...
    # cat old.txt old.txt new.txt | sort | uniq -c | grep " 2 " | sed -e's|[ ][ ]*2 ||' | xargs rm -f
  fi

  if [[ -f $GPU_SYSTEM_ROOT/etc/gpu-features-available.sh ]]; then
    source $GPU_SYSTEM_ROOT/etc/gpu-features-available.sh
  fi
  if [[ -n $ONNXRUNTIME_REVISION ]]; then
    source $ONNXRUNTIME_ROOT/etc/ort-init.sh
  fi

  cmake --build . -- ${JOBS:+-j$JOBS} install
  mkdir -p $INSTALLROOT/etc/modulefiles && rsync -a --delete etc/modulefiles/ $INSTALLROOT/etc/modulefiles
  # install the compilation database so that we can post-check the code
  cp ${BUILDDIR}/compile_commands.json ${INSTALLROOT}

  DEVEL_SOURCES="`readlink $SOURCEDIR || echo $SOURCEDIR`"
  # This really means we are in development mode. We need to make sure we
  # use the real path for sources in this case. We also copy the
  # compile_commands.json file so that IDEs can make use of it directly, this
  # is a departure from our "no changes in sourcecode" policy, but for a good reason
  # and in any case the file is in gitignore.
  if [ "$DEVEL_SOURCES" != "$SOURCEDIR" ]; then
    perl -p -i -e "s|$SOURCEDIR|$DEVEL_SOURCES|" compile_commands.json
    ln -sf $BUILDDIR/compile_commands.json $DEVEL_SOURCES/compile_commands.json
  fi
  if [[ $ALIBUILD_O2_TESTS ]]; then
    export O2_ROOT=$INSTALLROOT
    export VMCWORKDIR=$O2_ROOT/share
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$O2_ROOT/lib
    if [[ ! $BOOST_VERSION && $ARCHITECTURE == osx* ]]; then
      export ROOT_INCLUDE_PATH=$(brew --prefix boost)/include:$ROOT_INCLUDE_PATH
    fi
    if [[ -z $OPENSSL_REVISION && $ARCHITECTURE == osx* ]]; then
      export ROOT_INCLUDE_PATH=$(brew --prefix openssl@3)/include:$ROOT_INCLUDE_PATH
    fi
    export ROOT_INCLUDE_PATH=$INSTALLROOT/include:$INSTALLROOT/include/GPU:$ROOT_INCLUDE_PATH
    # Set Geant4 data sets environment
    if [[ "$G4INSTALL" != "" ]]; then
      `$G4INSTALL/bin/geant4-config --datasets | sed 's/[^ ]* //' | sed 's/G4/export G4/' | sed 's/DATA /DATA=/'`
    fi
    # Clean up old coverage data and tests logs
    find . -name "*.gcov" -o -name "*.gcda" -delete
    # cleanup ROOT files created by tests in build area
    find $PWD -name "*.root" -delete
    rm -rf test_logs
    TESTERR=
    ctest -C ${CMAKE_BUILD_TYPE} -E "test_Framework" --output-on-failure ${JOBS+-j $JOBS} || TESTERR=$?
    ctest -C ${CMAKE_BUILD_TYPE} -R test_Framework --output-on-failure || TESTERR=$?
    # Display additional logs for tests that timed out in a non-fatal way
    set +x
    for LOG in test_logs/*.nonfatal; do
      [[ -e $LOG ]] || continue
      printf "\n\n\n\n\n\n"
      cat "$LOG"
      printf "\n\n\n\n\n\n"
    done
    set -x
    [[ ! $TESTERR ]] || exit 1
  fi
  # Create code coverage information to be uploaded
  # by the calling driver to codecov.io or similar service
  if [[ $CMAKE_BUILD_TYPE == COVERAGE ]]; then
    rm -rf coverage.info
    lcov --base-directory $SOURCEDIR --directory . --capture --output-file coverage.info
    lcov --remove coverage.info '*/usr/*' --output-file coverage.info
    lcov --remove coverage.info '*/boost/*' --output-file coverage.info
    lcov --remove coverage.info '*/ROOT/*' --output-file coverage.info
    lcov --remove coverage.info '*/FairRoot/*' --output-file coverage.info
    lcov --remove coverage.info '*/G__*Dict*' --output-file coverage.info
    perl -p -i -e "s|$SOURCEDIR||g" coverage.info # Remove the absolute path for sources
    perl -p -i -e "s|$BUILDDIR||g" coverage.info # Remove the absolute path for generated files
    perl -p -i -e "s|^[0-9]+/||g" coverage.info # Remove PR location path
    lcov --list coverage.info
  fi

  if [[ ( "$ALIBOT_PR_REPO" == "AliceO2Group/AliceO2" || "$ALIBOT_PR_REPO" == "alisw/alidist" ) && $ALIBUILD_O2_FORCE_GPU == 1 ]]; then
    GPUCA_STANDALONE_CI=1 $SOURCEDIR/GPU/GPUTracking/Standalone/cmake/build.sh $SOURCEDIR
  fi

valid_defaults:
  - o2
  - o2-dataflow
  - o2-epn
  - o2-dev-fairroot
  - alo
  - o2-prod
  - ali
---
#!/bin/sh
export ROOTSYS=$ROOT_ROOT

if [[ -n "$ALIBUILD_CONFIG_DIR" && -f "$ALIBUILD_CONFIG_DIR/resources/FindO2GPU.cmake" ]] && \
  ! cmp -s "$ALIBUILD_CONFIG_DIR/resources/FindO2GPU.cmake" "$SOURCEDIR/dependencies/FindO2GPU.cmake" && \
  [[ ! $(grep "# FindO2GPU.cmake Version " "$ALIBUILD_CONFIG_DIR/resources/FindO2GPU.cmake" | awk '{print $4}') -gt \
    $(grep "# FindO2GPU.cmake Version " "$SOURCEDIR/dependencies/FindO2GPU.cmake" | awk '{print $4}') ]]; then
  echo "FindO2GPU.cmake differs in O2 compared to alidist"
  exit 1
fi

if [[ -f $GPU_SYSTEM_ROOT/etc/gpu-features-available.sh ]]; then
  source $GPU_SYSTEM_ROOT/etc/gpu-features-available.sh
fi
if [[ -n $ONNXRUNTIME_REVISION ]]; then
  source $ONNXRUNTIME_ROOT/etc/ort-init.sh
fi

# Making sure people do not have SIMPATH set when they build fairroot.
# Unfortunately SIMPATH seems to be hardcoded in a bunch of places in
# fairroot, so this really should be cleaned up in FairRoot itself for
# maximum safety.
unset SIMPATH

case $ARCHITECTURE in
  osx*)
    # If we preferred system tools, we need to make sure we can pick them up.
    [[ ! $CURL_ROOT ]] && CURL_ROOT=`brew --prefix curl`
    [[ ! $BOOST_ROOT ]] && BOOST_ROOT=`brew --prefix boost`
    [[ ! $ZEROMQ_ROOT ]] && ZEROMQ_ROOT=`brew --prefix zeromq`
    [[ ! $GSL_ROOT ]] && GSL_ROOT=`brew --prefix gsl`
    [[ ! $PROTOBUF_ROOT ]] && PROTOBUF_ROOT=`brew --prefix protobuf`
    [[ ! $GLFW_ROOT ]] && GLFW_ROOT=`brew --prefix glfw`
    [[ ! $FMT_ROOT ]] && FMT_ROOT=`brew --prefix fmt`
  ;;
esac

# This affects only PR checkers
if [[ $ALIBUILD_O2_TESTS ]]; then
  # Impose extra errors.
  CXXFLAGS="${CXXFLAGS} -Werror -Wno-error=deprecated-declarations"
  # On OSX CI, we do not want to run the GUI, even if available.
  case $ARCHITECTURE in
    osx*) DPL_TESTS_BATCH_MODE=ON ;;
    *) ;;
  esac
fi

# Use ninja if in devel mode, ninja is found and DISABLE_NINJA is not 1
if [[ ! $CMAKE_GENERATOR && $DISABLE_NINJA != 1 && $DEVEL_SOURCES != $SOURCEDIR ]]; then
  NINJA_BIN=ninja-build
  type "$NINJA_BIN" &> /dev/null || NINJA_BIN=ninja
  type "$NINJA_BIN" &> /dev/null || NINJA_BIN=
  [[ $NINJA_BIN ]] && CMAKE_GENERATOR=Ninja || true
  unset NINJA_BIN
fi


unset DYLD_LIBRARY_PATH
cmake $SOURCEDIR -DCMAKE_INSTALL_PREFIX=$INSTALLROOT                                                      \
      ${CMAKE_GENERATOR:+-G "$CMAKE_GENERATOR"}                                                           \
      ${CMAKE_BUILD_TYPE:+-DCMAKE_BUILD_TYPE=$CMAKE_BUILD_TYPE}                                           \
      ${ALIBUILD_O2_TESTS:+-DENABLE_CASSERT=ON}                                                           \
      ${DPL_TESTS_BATCH_MODE:+-DDPL_TESTS_BATCH_MODE=${DPL_TESTS_BATCH_MODE}}                             \
      -DCMAKE_EXPORT_COMPILE_COMMANDS=ON                                                                  \
      ${CXXSTD:+-DCMAKE_CXX_STANDARD=$CXXSTD}                                                             \
      ${LIBJALIENO2_ROOT:+-DlibjalienO2_ROOT=$LIBJALIENO2_ROOT}                                           \
      ${XROOTD_REVISION:+-DXROOTD_DIR=$XROOTD_ROOT}                                                       \
      ${JALIEN_ROOT_REVISION:+-DJALIEN_ROOT_ROOT=$JALIEN_ROOT_ROOT}                                       \
      ${GPUCA_BUILD_EVENT_DISPLAY:+-GPUCA_BUILD_EVENT_DISPLAY=${GPUCA_BUILD_EVENT_DISPLAY}}               \
      -DENABLE_CUDA="${O2_GPU_CUDA_AVAILABLE:-AUTO}"                                                      \
      -DENABLE_HIP="${O2_GPU_ROCM_AVAILABLE:-AUTO}"                                                       \
      -DENABLE_OPENCL="${O2_GPU_OPENCL_AVAILABLE:-AUTO}"                                                  \
      ${O2_GPU_ROCM_AVAILABLE_ARCH:+-DHIP_AMDGPUTARGET="${O2_GPU_ROCM_AVAILABLE_ARCH}"}                   \
      ${O2_GPU_CUDA_AVAILABLE_ARCH:+-DCUDA_COMPUTETARGET="${O2_GPU_CUDA_AVAILABLE_ARCH}"}                 \
      ${CURL_ROOT:+-DCURL_ROOT=$CURL_ROOT}                                                                \
      ${LIBUV_ROOT:+-DLibUV_ROOT=$LIBUV_ROOT}                                                             \
      ${BUILD_ANALYSIS:+-DBUILD_ANALYSIS=$BUILD_ANALYSIS}                                                 \
      ${BUILD_EXAMPLES:+-DBUILD_EXAMPLES=$BUILD_EXAMPLES}                                                 \
      ${BUILD_TEST_ROOT_MACROS:+-BUILD_TEST_ROOT_MACROS=$BUILD_TEST_ROOT_MACROS}                          \
      ${ENABLE_UPGRADES:+-DENABLE_UPGRADES=$ENABLE_UPGRADES}                                              \
      ${ARROW_ROOT:+-DGandiva_DIR=$ARROW_ROOT/lib/cmake/Gandiva}                                          \
      ${ARROW_ROOT:+-DArrow_DIR=$ARROW_ROOT/lib/cmake/Arrow}                                              \
      ${CLANG_REVISION:+-DCLANG_EXECUTABLE="$CLANG_ROOT/bin-safe/clang"}                                  \
      ${CLANG_REVISION:+-DLLVM_LINK_EXECUTABLE="$CLANG_ROOT/bin/llvm-link"}                               \
      ${ITSRESPONSE_ROOT:+-DITSRESPONSE=${ITSRESPONSE_ROOT}}                                              \
      ${ORT_ROCM_BUILD:+-DORT_ROCM_BUILD=${ORT_ROCM_BUILD}}                                               \
      ${ORT_CUDA_BUILD:+-DORT_CUDA_BUILD=${ORT_CUDA_BUILD}}                                               \
      ${ORT_MIGRAPHX_BUILD:+-DORT_MIGRAPHX_BUILD=${ORT_MIGRAPHX_BUILD}}                                   \
      ${ORT_TENSORRT_BUILD:+-DORT_TENSORRT_BUILD=${ORT_TENSORRT_BUILD}}
# LLVM_ROOT is required for Gandiva

cmake --build . -- ${JOBS+-j $JOBS} install

# install the compilation database so that we can post-check the code
cp compile_commands.json ${INSTALLROOT}

DEVEL_SOURCES="`readlink $SOURCEDIR || echo $SOURCEDIR`"
# This really means we are in development mode. We need to make sure we
# use the real path for sources in this case. We also copy the
# compile_commands.json file so that IDEs can make use of it directly, this
# is a departure from our "no changes in sourcecode" policy, but for a good reason
# and in any case the file is in gitignore.
if [ "$DEVEL_SOURCES" != "$SOURCEDIR" ]; then
  perl -p -i -e "s|$SOURCEDIR|$DEVEL_SOURCES|" compile_commands.json
  ln -sf $BUILDDIR/compile_commands.json $DEVEL_SOURCES/compile_commands.json
fi

if [[ ( "$ALIBOT_PR_REPO" == "AliceO2Group/AliceO2" || "$ALIBOT_PR_REPO" == "alisw/alidist" ) && $ALIBUILD_O2_FORCE_GPU == 1 ]]; then
  GPUCA_STANDALONE_CI=1  $SOURCEDIR/GPU/GPUTracking/Standalone/cmake/build.sh $SOURCEDIR
fi

# Modulefile
mkdir -p etc/modulefiles
cat > etc/modulefiles/$PKGNAME <<EoF
#%Module1.0
proc ModulesHelp { } {
  global version
  puts stderr "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
}
set version $PKGVERSION-@@PKGREVISION@$PKGHASH@@
module-whatis "ALICE Modulefile for $PKGNAME $PKGVERSION-@@PKGREVISION@$PKGHASH@@"
# Dependencies
module load BASE/1.0 \\
            FairRoot/$FAIRROOT_VERSION-$FAIRROOT_REVISION                                           \\
            ${DDS_REVISION:+DDS/$DDS_VERSION-$DDS_REVISION}                                         \\
            ${GCC_TOOLCHAIN_REVISION:+GCC-Toolchain/$GCC_TOOLCHAIN_VERSION-$GCC_TOOLCHAIN_REVISION} \\
            ${VC_REVISION:+Vc/$VC_VERSION-$VC_REVISION}                                             \\
            ${HEPMC3_REVISION:+HepMC3/$HEPMC3_VERSION-$HEPMC3_REVISION}                             \\
            ${MONITORING_REVISION:+Monitoring/$MONITORING_VERSION-$MONITORING_REVISION}             \\
            ${CONFIGURATION_REVISION:+Configuration/$CONFIGURATION_VERSION-$CONFIGURATION_REVISION} \\
            ${LIBINFOLOGGER_REVISION:+libInfoLogger/$LIBINFOLOGGER_VERSION-$LIBINFOLOGGER_REVISION} \\
            ${COMMON_O2_REVISION:+Common-O2/$COMMON_O2_VERSION-$COMMON_O2_REVISION}                 \\
            ms_gsl/$MS_GSL_VERSION-$MS_GSL_REVISION                                                 \\
            ${ARROW_REVISION:+arrow/$ARROW_VERSION-$ARROW_REVISION}                                 \\
            ${DEBUGGUI_REVISION:+DebugGUI/$DEBUGGUI_VERSION-$DEBUGGUI_REVISION}                     \\
            ${LIBUV_REVISION:+libuv/$LIBUV_VERSION-$LIBUV_REVISION}                                 \\
            ${JALIEN_ROOT_REVISION:+JAliEn-ROOT/$JALIEN_ROOT_VERSION-$JALIEN_ROOT_REVISION}         \\
            ${FASTJET_REVISION:+fastjet/$FASTJET_VERSION-$FASTJET_REVISION}                         \\
            ${CGAL_REVISION:+cgal/$CGAL_VERSION-$CGAL_REVISION}                                     \\
            ${GLFW_REVISION:+GLFW/$GLFW_VERSION-$GLFW_REVISION}                                     \\
            ${FMT_REVISION:+fmt/$FMT_VERSION-$FMT_REVISION}                                         \\
            ${AEGIS_REVISION:+AEGIS/$AEGIS_VERSION-$AEGIS_REVISION}                                 \\
            ${LIBJALIENO2_REVISION:+libjalienO2/$LIBJALIENO2_VERSION-$LIBJALIENO2_REVISION}         \\
            ${CURL_REVISION:+curl/$CURL_VERSION-$CURL_REVISION}                                     \\
            ${FAIRMQ_REVISION:+FairMQ/$FAIRMQ_VERSION-$FAIRMQ_REVISION}                             \\
            ${FFTW3_REVISION:+FFTW3/$FFTW3_VERSION-$FFTW3_REVISION}                                 \\
            ${ONNXRUNTIME_REVISION:+ONNXRuntime/$ONNXRUNTIME_VERSION-$ONNXRUNTIME_REVISION}         \\
            ${RAPIDJSON_REVISION:+RapidJSON/$RAPIDJSON_VERSION-$RAPIDJSON_REVISION}                 \\
            ${NLOHMANN_JSON_REVISION:+nlohmann_json/$NLOHMANN_JSON_VERSION-$NLOHMANN_JSON_REVISION} \\
            ${MLMODELS_REVISION:+MLModels/$MLMODELS_VERSION-$MLMODELS_REVISION}                     \\
            ${BOOKKEEPING_API_REVISION:+bookkeeping-api/$BOOKKEEPING_API_VERSION-$BOOKKEEPING_API_REVISION}

# Our environment
set O2_ROOT \$::env(BASEDIR)/$PKGNAME/\$version
setenv O2_ROOT \$O2_ROOT
setenv VMCWORKDIR \$O2_ROOT/share

set O2_ROOT \$O2_ROOT
prepend-path PATH \$O2_ROOT/bin
prepend-path LD_LIBRARY_PATH \$O2_ROOT/lib
prepend-path ROOT_DYN_PATH \$O2_ROOT/lib
$([[ ${ARCHITECTURE:0:3} == osx && ! $BOOST_VERSION ]] && echo "prepend-path ROOT_INCLUDE_PATH $BOOST_ROOT/include")
prepend-path ROOT_INCLUDE_PATH \$O2_ROOT/include/GPU
prepend-path ROOT_INCLUDE_PATH \$O2_ROOT/include
EoF
mkdir -p $INSTALLROOT/etc/modulefiles && rsync -a --delete etc/modulefiles/ $INSTALLROOT/etc/modulefiles

if [[ $ALIBUILD_O2_TESTS ]]; then
  export O2_ROOT=$INSTALLROOT
  export VMCWORKDIR=$O2_ROOT/share
  export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$O2_ROOT/lib
  if [[ ! $BOOST_VERSION && $ARCHITECTURE == osx* ]]; then
    export ROOT_INCLUDE_PATH=$(brew --prefix boost)/include:$ROOT_INCLUDE_PATH
  fi
  if [[ -z $OPENSSL_REVISION && $ARCHITECTURE == osx* ]]; then
    export ROOT_INCLUDE_PATH=$(brew --prefix openssl@3)/include:$ROOT_INCLUDE_PATH
  fi
  export ROOT_INCLUDE_PATH=$INSTALLROOT/include:$INSTALLROOT/include/GPU:$ROOT_INCLUDE_PATH
  # Clean up old coverage data and tests logs
  find . -name "*.gcov" -o -name "*.gcda" -delete
  rm -rf test_logs
  # Clean up ROOT files created by tests in build area
  find $PWD -name "*.root" -delete
  TESTERR=
  ctest -C ${CMAKE_BUILD_TYPE} -E "(test_Framework)|(test_GPUsort(CUDA|HIP))" --output-on-failure ${JOBS+-j $JOBS} || TESTERR=$?
  ctest -C ${CMAKE_BUILD_TYPE} -R test_Framework --output-on-failure || TESTERR=$?
  # Display additional logs for tests that timed out in a non-fatal way
  set +x
  for LOG in test_logs/*.nonfatal; do
    [[ -e $LOG ]] || continue
    printf "\n\n\n\n\n\n"
    cat "$LOG"
    printf "\n\n\n\n\n\n"
  done
  set -x
  [[ ! $TESTERR ]] || exit 1
fi

# Create code coverage information to be uploaded
# by the calling driver to codecov.io or similar service
if [[ $CMAKE_BUILD_TYPE == COVERAGE ]]; then
  rm -rf coverage.info
  lcov --base-directory $SOURCEDIR --directory . --capture --output-file coverage.info
  lcov --remove coverage.info '*/usr/*' --output-file coverage.info
  lcov --remove coverage.info '*/boost/*' --output-file coverage.info
  lcov --remove coverage.info '*/ROOT/*' --output-file coverage.info
  lcov --remove coverage.info '*/FairRoot/*' --output-file coverage.info
  lcov --remove coverage.info '*/G__*Dict*' --output-file coverage.info
  perl -p -i -e "s|$SOURCEDIR||g" coverage.info # Remove the absolute path for sources
  perl -p -i -e "s|$BUILDDIR||g" coverage.info # Remove the absolute path for generated files
  perl -p -i -e "s|^[0-9]+/||g" coverage.info # Remove PR location path
  lcov --list coverage.info
fi
