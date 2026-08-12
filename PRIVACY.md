# Kaido Routes Privacy Policy

Effective date: August 12, 2026

Kaido Routes is a route-first driving navigation app. This policy describes
the behavior of the current open-source iPhone release.

## Data collection

Kaido Routes does not collect personal data, use advertising or analytics
SDKs, create user accounts, or track people across apps or websites.

When the user chooses Current Location or explicitly starts released-route
navigation, the app may process precise location, heading, speed, accuracy,
and timestamp observations on the device. These observations are used to
choose an origin or estimate progress on the selected route. Raw observation
samples are not transmitted to the Kaido Routes project or retained in the
navigation checkpoint.

Development builds include an internal calibration mode that can keep raw
location observations in memory during an explicitly started session. It is
not available in the distributed Release product. Raw observations are not
persisted by the app. Only a coordinate-free report can be exported
deliberately by the tester.

## Data stored on the device

The app stores interface, voice, and map-display preferences in its private
container. To restore an unfinished journey, its navigation checkpoint may
store the chosen origin and destination, their coordinates, search text,
ordinary-road access and egress geometry and instructions, the exact route,
and route progress. It may also store user-created route documents and signed
pre-drive information imported by the user. This data stays in the app
container unless the user deliberately exports a route document or a
development-build calibration report. Finishing, ending, or resetting a
journey removes its checkpoint.

Deleting the app removes its private container. Location access can be revoked
at any time in iOS Settings. The app does not require an account, so there is
no server-side account or personal-data record to delete.

## Network and external services

Kaido Routes has no server of its own: neither location nor route progress is
sent to a Kaido Routes service. Two network paths do exist.

Apple Maps supplies the ordinary-road legs between the driver's position and
the chosen entrance, and the exit and destination, and it backs destination
search. Those requests go to Apple and carry the coordinates or search text
they need; Apple's privacy practices apply to them.

Links to official road information, map-data attribution, licences, and this
policy open external websites; those sites apply their own privacy practices.

A later release that adds another network service must update this policy and
its App Store privacy disclosures before distribution.

## Required-reason APIs

The bundled privacy manifest declares:

- app-private `UserDefaults`, used for local preferences; and
- system uptime, used only to measure elapsed time for in-app operations.

Neither use is for fingerprinting or tracking.

## Contact

Privacy questions may be raised through the
[Kaido Routes issue tracker](https://github.com/Awakehsh/kaido-routes/issues).
Issues are public, so do not include precise locations or other personal
information. For a private request, use the developer contact shown on the
Kaido Routes App Store product page.
