# Asta Matrix — Privacy Policy (DRAFT)

**Draft date: 10 August 2026**

> This document is a technical draft based on the current MVP codebase. Before public release it must be reviewed, supplied with the publisher's legal/contact details, hosted at a stable public URL, and aligned with the final store data-safety declarations.

## Service

Asta Matrix is an independent fantasy-football auction management application. It lets authenticated users import a player dataset, configure an auction, manage bids and rosters, and synchronize an auction session across devices.

## Data processed by the current MVP

### Account data

Authentication is provided through Firebase Authentication. Depending on the sign-in method, the application may process:

- Firebase user identifier (UID);
- email address;
- display name;
- profile photo URL;
- authentication provider identifiers;
- login timestamps.

A limited profile copy is stored in Firestore under the authenticated user's UID.

### Auction data

The application stores data necessary to provide and restore auction sessions, including:

- auction name and configuration;
- fantasy team names;
- budgets and roster state;
- immutable auction events such as nominations, bids, assignments and undo operations;
- minimal realtime state used for the shared countdown and controller handoff.

### User-imported player data

When a user imports a CSV, TSV or TXT file, the application reads the selected file in order to build the auction dataset. The resulting normalized player records used by the auction are stored inside that auction's Firestore session snapshot so that the session can be restored later.

Users should import only data they are entitled to use.

## Purpose of processing

The MVP processes these data to:

- authenticate the user;
- create, synchronize and restore auction sessions;
- maintain budgets and rosters;
- provide realtime countdown and controller/viewer coordination;
- calculate in-app Matrix recommendations.

## Third-party infrastructure

The current MVP uses Google Firebase services, including Firebase Authentication and Cloud Firestore. Google processes technical data according to the terms and privacy documentation applicable to Firebase services.

The application also supports Google Sign-In when selected by the user.

## Analytics, advertising and sale of data

The current MVP codebase does not integrate an advertising SDK or a dedicated analytics SDK, and Asta Matrix does not implement a mechanism to sell personal data to advertisers.

This section must be re-checked if analytics, crash reporting, advertising, subscriptions or additional SDKs are introduced before release.

## Data retention and deletion

Auction and account data are retained while needed to provide the account and restore saved sessions, unless a shorter retention period is adopted before release.

**Release blocker:** the final public build must provide the account-deletion flow and the publisher must define the final retention/deletion procedure before this draft can be published as the production Privacy Policy.

## Security

Firestore access is restricted through authentication and security rules. Auction data are scoped to session owners/members, while write privileges for the MVP auction controller remain restricted to the session owner.

No technical system can guarantee absolute security; the application and Firebase configuration should be kept updated and monitored.

## Independent product notice

Asta Matrix is an independent software product. It does not automatically scrape third-party fantasy-football platforms in the current MVP flow and does not claim affiliation, sponsorship or approval by third-party fantasy-football services.

## Children's privacy

The publisher must define the intended age rating and any age restrictions before store publication. The current MVP does not intentionally implement features specifically directed at children.

## Changes to this policy

The production policy should include a version/effective date and be updated when the application's data processing, SDKs or business model materially change.

## Contact

**Release blocker:** insert the publisher/controller's legal identity and a monitored privacy/support email address before publication.
