// Entry point. All real work lives in the Murmur library; this
// target is only here because SPM needs an `.executable` product and
// the library depends on it being loaded from a bundled process.
import Murmur

MurmurLauncher.run()
