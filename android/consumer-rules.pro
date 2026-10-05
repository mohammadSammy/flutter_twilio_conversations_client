# Applied to every app that uses this plugin.
#
# Twilio's shared-internal pulls in androidx.security:security-crypto, whose Tink
# dependency references Error Prone and JSR 305 annotations that only exist at compile time.
# Without this, R8 fails release builds with "Missing class
# com.google.errorprone.annotations.Immutable". Twilio's own rules cover com.twilio.** only.
-dontwarn com.google.errorprone.annotations.**
-dontwarn javax.annotation.concurrent.**
