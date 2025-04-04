-keep class skip.** { *; }
-keep class tools.skip.** { *; }
-keep class kotlin.jvm.functions.** {*;}
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-dontwarn java.awt.**

# Gets rid of the warning,
#   Missing class com.google.errorprone.annotations.Immutable
#   (referenced from: com.google.crypto.tink.util.Bytes)
# Should be safe to use. See:
#   https://github.com/google/tink/issues/536
#   https://issuetracker.google.com/issues/195752905
-dontwarn com.google.errorprone.annotations.Immutable

