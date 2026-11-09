# Kotlin compiler cache pins

The Android CI prefetches only the compiler JARs and POMs pinned in
`kotlin_compiler_checksums.json` from the two official Maven Central endpoints.
The versions remain those used by Flutter 3.47.7's included Gradle build
(2.2.21) and this app's `android/settings.gradle.kts` (2.4.0).

The files were downloaded from `https://repo.maven.apache.org/maven2/` on
2026-11-09, checked against Maven Central's published `.sha1` files, and then
hashed with SHA-256 to create the immutable pins. CI verifies SHA-256 before
publishing files into the local Maven repository. It does not change compiler
versions or disable Gradle verification.

Gradle can reuse local Maven artifacts after checking the remote checksum:
<https://docs.gradle.org/current/userguide/dependency_caching.html#sec:checksum_based_storage>.

When upgrading Flutter or Kotlin, review the new official artifacts and update
both the version list in the workflow and this checksum manifest.
