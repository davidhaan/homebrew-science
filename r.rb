class RDownloadStrategy < SubversionDownloadStrategy
  def stage
    quiet_safe_system "cp", "-r", @clone, Dir.pwd
    Dir.chdir cache_filename
  end
end

class R < Formula
  homepage "http://www.r-project.org/"
  url "http://cran.rstudio.com/src/base/R-3/R-3.1.3.tar.gz"
  mirror "http://cran.r-project.org/src/base/R-3/R-3.1.3.tar.gz"
  sha256 "07e98323935baa38079204bfb9414a029704bb9c0ca5ab317020ae521a377312"

  bottle do
    root_url "https://homebrew.bintray.com/bottles-science"
    sha256 "ded0eb716b80d099999b61b4c2b54fc51f5b3097bdb7c0934cf0b6dbc8366f8f" => :yosemite
    sha256 "388232be637e3a35b58e829f8a8ef0d05ae2933d84ed92c9ebef488246407506" => :mavericks
    sha256 "ba6aa9cdd484947ffbcdc6549f7884c089eb15c1eba44921d9fb6b6c6dfddb19" => :mountain_lion
  end

  head do
    url "https://svn.r-project.org/R/trunk", :using => RDownloadStrategy
    depends_on :tex
  end

  option "without-accelerate", "Build without the Accelerate framework (use Rblas)"
  option "without-check", "Skip build-time tests (not recommended)"
  option "without-tcltk", "Build without Tcl/Tk"
  option "with-librmath-only", "Only build standalone libRmath library"

  depends_on :fortran
  depends_on "readline"
  depends_on "gettext"
  depends_on "libtiff"
  depends_on "jpeg"
  depends_on "cairo" if OS.mac?
  depends_on :x11 => :recommended
  depends_on "valgrind" => :optional
  depends_on "openblas" => :optional

  # This is the same script that Debian packages use.
  resource "completion" do
    url "https://rcompletion.googlecode.com/svn-history/r31/trunk/bash_completion/R", :using => :curl
    sha256 "2b5cac905ab5dd4889e8a356bbdf2dddff60f718a4104b169e48ca856716e705"
    version "r31"
  end

  patch :DATA

  def install
    args = [
      "--prefix=#{prefix}",
      "--with-libintl-prefix=#{Formula["gettext"].opt_prefix}",
      "--enable-memory-profiling",
    ]

    if OS.linux?
      args << "--enable-R-shlib"
      # If LDFLAGS contains any -L options, configure sets LD_LIBRARY_PATH to
      # search those directories. Remove -LHOMEBREW_PREFIX/lib from LDFLAGS.
      ENV.remove "LDFLAGS", "-L#{HOMEBREW_PREFIX}/lib"
    else
      args << "--enable-R-framework"

      # Disable building against the Aqua framework with CLT >= 6.0.
      # See https://gcc.gnu.org/bugzilla/show_bug.cgi?id=63651
      # This should be revisited when new versions of GCC come along.
      if ENV.compiler != :clang && MacOS::CLT.version >= "6.0"
        args << "--without-aqua"
      else
        args << "--with-aqua"
      end
    end

    if build.with? "valgrind"
      args << "--with-valgrind-instrumentation=2"
      ENV.Og
    end

    if build.with? "openblas"
      args << "--with-blas=-L#{Formula["openblas"].opt_lib} -lopenblas" << "--with-lapack"
      ENV.append "LDFLAGS", "-L#{Formula["openblas"].opt_lib}"
    elsif build.with? "accelerate"
      args << "--with-blas=-framework Accelerate" << "--with-lapack"
      ENV.append_to_cflags "-D__ACCELERATE__" if ENV.compiler != :clang
      # Fall back to Rblas without-accelerate or -openblas
    end

    args << "--without-tcltk" if build.without? "tcltk"
    args << "--without-x" if build.without? "x11"

    # Also add gettext include so that libintl.h can be found when installing packages.
    ENV.append "CPPFLAGS", "-I#{Formula["gettext"].opt_include}"
    ENV.append "LDFLAGS",  "-L#{Formula["gettext"].opt_lib}"

    # Sometimes the wrong readline is picked up.
    ENV.append "CPPFLAGS", "-I#{Formula["readline"].opt_include}"
    ENV.append "LDFLAGS",  "-L#{Formula["readline"].opt_lib}"

    # Pull down recommended packages if building from HEAD.
    system "./tools/rsync-recommended" if build.head?

    system "./configure", *args

    if build.without? "librmath-only"
      system "make"
      ENV.deparallelize # Serialized installs, please
      system "make check 2>&1 | tee make-check.log" if build.with? "check"
      system "make", "install"

      # Link binaries, headers, libraries, & manpages from the Framework
      # into the normal locations
      if OS.mac?
        bin.install_symlink prefix/"R.framework/Resources/bin/R"
        bin.install_symlink prefix/"R.framework/Resources/bin/Rscript"
        frameworks.install_symlink prefix/"R.framework"
        include.install_symlink prefix/"R.framework/Resources/include/R.h"
        lib.install_symlink prefix/"R.framework/Resources/lib/libR.dylib"
        man1.install_symlink prefix/"R.framework/Resources/man1/R.1"
        man1.install_symlink prefix/"R.framework/Resources/man1/Rscript.1"
      end

      bash_completion.install resource("completion")

      prefix.install "make-check.log" if build.with? "check"
    end

    cd "src/nmath/standalone" do
      system "make"
      ENV.deparallelize # Serialized installs, please
      system "make", "install"

      if OS.mac?
        lib.install_symlink Dir[prefix/"R.framework/Versions/[0-9]*/Resources/lib/libRmath.dylib"]
        include.install_symlink Dir[prefix/"R.framework/Versions/[0-9]*/Resources/include/Rmath.h"]
      end
    end
  end

  test do
    if build.without? "librmath-only"
      (testpath / "test.R").write("print(1+1);")
      system "r < test.R --no-save"
      system "rscript", "test.R"
    end
  end

  def caveats
    if build.without? "librmath-only" then <<-EOS.undent
      If you would like your installed R packages to survive minor R upgrades,
      you can run:
        mkdir -p ~/Library/R/#{xy}/library
      so R will preferentially install packages under your home directory
      instead of in the Cellar.

      To enable rJava support, run the following command:
        R CMD javareconf JAVA_CPPFLAGS=-I/System/Library/Frameworks/JavaVM.framework/Headers
      If you've installed a version of Java other than the default, you might need to instead use:
        R CMD javareconf JAVA_CPPFLAGS="-I/System/Library/Frameworks/JavaVM.framework/Headers -I/Library/Java/JavaVirtualMachines/jdk<version>.jdk/"
        (where <version> can be found by running `java -version` or `locate jni.h`)
      EOS
    end
  end

  def xy
    stable.version.to_s.slice(/(\d.\d)/)
  end
end

__END__
diff --git a/src/modules/lapack/vecLibg95c.c b/src/modules/lapack/vecLibg95c.c
index ffc18e4..6728244 100644
--- a/src/modules/lapack/vecLibg95c.c
+++ b/src/modules/lapack/vecLibg95c.c
@@ -2,6 +2,12 @@
 #include <config.h>
 #endif
 
+#ifndef __has_extension
+#define __has_extension(x) 0
+#endif
+#define vImage_Utilities_h
+#define vImage_CVUtilities_h
+
 #include <AvailabilityMacros.h> /* for MAC_OS_X_VERSION_10_* -- present on 10.2+ (according to Apple) */
 /* Since OS X 10.8 vecLib requires Accelerate to be included first (which in turn includes vecLib) */
 #if defined MAC_OS_X_VERSION_10_8 && MAC_OS_X_VERSION_MIN_REQUIRED >= 1040

