# Signed pre-drive evidence updates

This directory is the public, project-controlled transport boundary for signed
Kaido Routes pre-drive evidence envelopes.

The iPhone app accepts an envelope only when its compile-time product
descriptor pins this exact HTTPS endpoint and Ed25519 trust key. It then
revalidates the signature, product release, RoutePlan, source registry, tariff
profile, chronology, and expiry before publishing any current information.

An envelope grants no route, navigation, location, or realtime-passage
authority. Expired or profile-incomplete evidence fails closed as current
information without revoking the independently validated route release.
