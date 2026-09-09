Specification 01 — Product Definition & Business Requirements

1. Purpose

1.1 What

The platform is a tourism reservation and commercial management system designed for tourism agencies that sell:

* Experiences.
* Accommodations.
* Predefined packages.
* Customized plans.
* Complementary services.

The platform SHALL allow the agency to manage its commercial catalog, receive customer requests, prepare quotations, verify availability, manage pre-reservations, confirm reservations, and monitor its business activity.

Customers SHALL be able to initiate requests through:

* The web platform.
* WhatsApp.

Internal users SHALL manage the complete operational process through the management application.

1.2 Why

The current business process relies heavily on WhatsApp and manual coordination.

A typical operation requires an operator to:

1. Receive the customer’s request.
2. Understand what the customer wants.
3. Contact the service provider.
4. Verify availability.
5. Calculate or negotiate the price.
6. Communicate the proposal to the customer.
7. Confirm the reservation.

This creates operational friction, increases the possibility of human error, makes information difficult to track, and limits the agency’s ability to scale.

The platform exists to transform this process into a structured, traceable, and partially automated business workflow while preserving the human verification required by the business.

⸻

2. Product Vision

2.1 What

The platform SHALL act as a central operating system for the tourism agency’s commercial reservation process.

It SHALL connect four fundamental elements:

Customer

↓

Product

↓

Commercial Request

↓

Reservation

The platform SHALL allow a customer request to evolve from an initial inquiry into a structured quotation, availability verification, and ultimately a confirmed reservation.

2.2 Why

The agency needs a single source of truth for its commercial operations.

The platform should eliminate the need to reconstruct the history of a customer interaction from conversations, spreadsheets, messages, and personal notes.

⸻

3. Core Business Model

3.1 What

The platform SHALL support a product-centered tourism business model.

The principal commercial entity SHALL be the Product.

A Product MAY represent:

* An Experience.
* An Accommodation.
* A predefined package.
* A customized commercial offering.

Products MAY contain configurable complementary services called Add-ons.

Examples:

* Transportation.
* Food.
* Drinks.
* Activities.
* Decorations.
* Equipment.
* Other complementary services.

3.2 Why

The agency’s commercial offering is not limited to fixed products.

Customers frequently need customized combinations.

The product model therefore needs to support both:

Predefined offering

and

Customized offering

without requiring the agency to create a new permanent product for every customer request.

⸻

4. Experiences

4.1 What

The system SHALL allow the agency to manage tourism experiences.

Experiences MAY belong to categories such as:

* Sea and beach.
* Day activities.
* Night activities.
* City experiences.
* Adventure.
* Gastronomy.
* Cultural experiences.
* Other agency-defined categories.

Categories SHALL be manageable by authorized internal users.

4.2 Why

Categories allow the agency to organize its commercial catalog and make products easier to discover, manage, classify, and report.

The system SHALL NOT assume that the initial categories are permanent.

⸻

5. Accommodations

5.1 What

The system SHALL allow the agency to manage accommodations as commercial products.

An accommodation MAY contain information necessary for customers and operators to understand what is being offered.

An accommodation MAY participate in:

* Individual reservations.
* Packages.
* Customized quotations.

5.2 Why

The agency sells both activities and lodging.

Both need to participate in the same commercial workflow so that a customer can create a combined travel plan instead of managing each component independently.

⸻

6. Packages

6.1 What

The system SHALL support predefined packages composed of one or more products and/or add-ons.

A package MAY define:

* Included products.
* Included services.
* Base commercial conditions.
* Default pricing.

A package SHALL remain customizable when the business rules allow it.

6.2 Why

Packages allow the agency to sell frequently requested combinations quickly while retaining the ability to adapt them to individual customers.

This reduces repetitive work without sacrificing personalization.

⸻

7. Product Customization

7.1 What

A customer request SHALL be customizable.

The customer or internal user MAY modify an existing offering by:

* Adding products.
* Removing optional components.
* Adding add-ons.
* Adjusting quantities where applicable.
* Selecting available options.

The resulting configuration SHALL be treated as a specific commercial proposal for that customer.

7.2 Why

Tourism products are frequently personalized.

The system must therefore support controlled variation without forcing operators to create permanent catalog products for temporary combinations.

⸻

8. Pricing

8.1 What

Prices SHALL be configurable by authorized internal users.

The platform SHALL support pricing at the appropriate commercial level, including:

* Product prices.
* Package prices.
* Add-on prices.
* Customized quotation prices.

The final commercial price MAY differ from the default catalog price when authorized.

8.2 Why

Tourism pricing can depend on:

* Customer requirements.
* Group size.
* Selected services.
* Season.
* Availability.
* Negotiation.
* Special commercial conditions.

The operator therefore needs controlled pricing flexibility.

⸻

9. Customer Requests

9.1 What

The platform SHALL allow customers to initiate a request without requiring the system to immediately create a confirmed reservation.

A request SHALL contain enough information to understand the customer’s intention.

Examples:

* Desired product.
* Desired date.
* Number of people.
* Accommodation requirements.
* Selected add-ons.
* Customer information.
* Additional notes.

Requests MAY originate from:

* Website.
* WhatsApp.

9.2 Why

Not every tourism request can be confirmed automatically.

The business currently requires an operator to verify availability with the service provider.

The system must therefore represent the customer’s intention before confirmation.

⸻

10. Pre-Reservation

10.1 What

The platform SHALL support a Pre-Reservation state.

A Pre-Reservation represents a customer’s request that has not yet been fully confirmed.

It SHALL allow the agency to maintain the commercial context while availability is being verified.

The Pre-Reservation MAY contain:

* Customer.
* Requested products.
* Requested dates.
* Requested quantities.
* Selected add-ons.
* Proposed price.
* Availability status.
* Internal notes.
* Verification status.

10.2 Why

This is a fundamental business requirement.

The agency cannot assume that a product is available merely because it exists in the catalog.

The current process requires an operator to contact the provider and confirm availability.

The system therefore needs a state between:

Customer request

and

Confirmed reservation.

⸻

11. Availability Verification

11.1 What

Authorized internal users SHALL be able to verify availability for a Pre-Reservation.

The verification MAY involve contacting the service provider manually.

The system SHALL record the outcome.

Possible outcomes SHOULD include:

* Available.
* Not available.
* Pending.
* Requires modification.

The system SHALL preserve the verification history when appropriate.

11.2 Why

Availability verification is a core operational activity.

Recording the result prevents the agency from depending exclusively on memory, WhatsApp conversations, or personal notes.

⸻

12. Quotation

12.1 What

The platform SHALL support the creation of quotations from customer requests or Pre-Reservations.

A quotation SHALL represent a commercial proposal containing:

* Customer.
* Selected products.
* Selected add-ons.
* Conditions.
* Price.
* Relevant dates.
* Status.

Authorized users SHALL be able to modify a quotation before confirmation.

Significant changes SHOULD remain auditable.

12.2 Why

The customer frequently needs a commercial proposal before making the final decision.

The quotation provides a structured representation of what the agency is offering.

⸻

13. Reservation

13.1 What

A Reservation SHALL represent a confirmed commercial commitment.

A Pre-Reservation SHALL NOT automatically become a Reservation merely because it exists.

Confirmation SHALL occur only when the required business conditions have been satisfied.

The Reservation SHALL preserve the final commercial configuration.

13.2 Why

The system must distinguish between:

* Something the customer requested.
* Something the agency proposed.
* Something that was verified.
* Something that was actually confirmed.

This distinction is essential for operational accuracy.

⸻

14. Reservation Lifecycle

14.1 What

The platform SHALL represent the lifecycle of a commercial request.

The conceptual flow SHALL be:

Request

→ Pre-Reservation

→ Availability Verification

→ Quotation

→ Confirmation

→ Reservation

The exact status model SHALL be refined during the domain and workflow specifications.

14.2 Why

Explicit lifecycle states provide operational clarity and prevent ambiguous records.

Every internal user should be able to understand what stage a customer operation is currently in.

⸻

15. Channels

15.1 What

The platform SHALL support two primary customer acquisition channels:

Web

Customers SHALL be able to browse relevant offerings and initiate reservation requests.

WhatsApp

Customers SHALL be able to initiate or continue the commercial process through WhatsApp.

The internal platform SHALL maintain the structured business information regardless of the originating channel.

15.2 Why

The agency already operates through WhatsApp.

The goal is not to force customers to abandon their preferred communication channel.

Instead, WhatsApp should become another entry point into the same structured reservation process.

⸻

16. Internal Users

16.1 What

The platform SHALL support authenticated internal users.

An initial administrator SHALL exist and SHALL be capable of creating additional users.

Users SHALL operate according to assigned roles and permissions.

The initial business model SHALL remain intentionally simple.

Operator and seller responsibilities MAY belong to the same user when the assigned permissions allow it.

16.2 Why

Different employees may perform different operations, but the business does not currently require a complex organizational hierarchy.

The system should provide enough access control to protect operations without creating unnecessary administrative complexity.

⸻

17. Roles and Permissions

17.1 What

The system SHALL support role-based access control.

Roles SHALL determine which operations a user can perform.

Permissions SHOULD be associated with business capabilities rather than individual screens.

Examples include:

* Manage products.
* Manage accommodations.
* Manage experiences.
* Manage categories.
* Manage add-ons.
* Manage prices.
* Manage customers.
* Manage quotations.
* Manage reservations.
* Verify availability.
* View reports.
* Manage users.

The initial role model SHALL remain simple and extensible.

17.2 Why

The system contains sensitive operational and customer information.

Not every internal user should be able to perform every operation.

At the same time, excessive role customization would introduce unnecessary complexity for the MVP.

⸻

18. Product Management

18.1 What

Authorized users SHALL be able to perform CRUD operations over the commercial catalog.

The product management capability SHALL support:

* Creation.
* Consultation.
* Modification.
* Activation/deactivation.
* Categorization.
* Pricing.
* Add-ons.
* Package relationships.

18.2 Why

The agency’s offering changes continuously.

Operators need to modify the catalog without requiring software development.

⸻

19. Customer Management

19.1 What

Authorized users SHALL be able to manage customer information relevant to reservations.

The system SHALL avoid collecting information that is not necessary for the business process.

Customer information SHALL be protected according to the project’s privacy principles.

19.2 Why

Customer information is necessary to operate reservations, but excessive data collection creates unnecessary privacy and security risks.

The system should follow a data-minimization approach.

⸻

20. Auditability

20.1 What

The system SHALL preserve meaningful history for important business operations.

Auditable actions SHOULD include:

* Changes to quotations.
* Changes to reservation status.
* Availability verification.
* Price changes affecting commercial operations.
* User administration.
* Relevant customer-data changes.

Audit information SHOULD identify:

* What changed.
* When it changed.
* Which user performed the action.

20.2 Why

Tourism operations involve multiple users and external providers.

When a commercial conflict occurs, the agency needs to understand what happened rather than rely on memory.

⸻

21. Reports and Statistics

21.1 What

The platform SHALL provide reporting and statistical capabilities for internal users.

The initial reporting capability SHOULD focus on business information such as:

* Number of requests.
* Pre-Reservations.
* Quotations.
* Confirmed Reservations.
* Sales.
* Product performance.
* Experience performance.
* Accommodation performance.
* Operational status.

Reports SHALL respect user permissions and tenant boundaries.

21.2 Why

The system should not only record transactions.

It should transform operational information into business knowledge.

The agency needs to understand what it sells, what converts, and where its business activity is concentrated.

⸻

22. Content Management

22.1 What

The public-facing platform SHALL support content-oriented information separately from transactional business information.

WordPress SHALL be considered the content management system for:

* Blog content.
* Marketing content.
* SEO-oriented pages.
* Editorial information.

Transactional business data SHALL remain outside WordPress.

22.2 Why

Marketing content changes frequently and may require non-technical content management.

Separating content from transactional data prevents the business domain from becoming dependent on the CMS.

⸻

23. Authentication and Session Security

23.1 What

Internal users SHALL authenticate before accessing protected management capabilities.

Sessions SHALL respect the user’s authorization context.

Access SHALL be revoked or restricted when the user’s permissions no longer allow the requested operation.

23.2 Why

The platform contains:

* Customer information.
* Commercial information.
* Prices.
* Reservations.
* Internal operational data.

Unauthorized access could cause financial, privacy, and operational damage.

⸻

24. Personal Data

24.1 What

The platform SHALL treat customer information as protected personal data.

The system SHALL follow:

* Data minimization.
* Purpose limitation.
* Appropriate access control.
* Appropriate retention.
* Secure handling.
* Auditable access where appropriate.

24.2 Why

The agency needs customer information to operate reservations, but personal data creates legal, security, and reputational responsibilities.

Privacy SHALL therefore be considered from the beginning rather than added later.

⸻

25. Tenant Readiness

25.1 What

The MVP MAY initially operate for a single tourism agency.

Nevertheless, the domain SHALL be designed so that business data can be associated with an organization/tenant.

The platform SHALL avoid assumptions that make multiple organizations impossible in the future.

25.2 Why

The long-term product may evolve from an internal agency system into a SaaS platform serving multiple tourism agencies.

Designing for tenant awareness now reduces future migration risk without requiring full multi-tenant functionality in the MVP.

⸻

26. Caching

26.1 What

The platform MAY use caching for information that is frequently requested and relatively stable.

Caching SHALL NOT become the authoritative source of business truth.

Business-critical information such as:

* Availability.
* Reservation state.
* Final pricing.
* Customer commitments.

SHALL be treated as authoritative data.

26.2 Why

Caching can improve performance, but stale information can create serious business problems.

For example, displaying outdated availability could result in an invalid reservation.

Therefore performance improvements must never compromise commercial correctness.

⸻

27. Integrations

27.1 What

The platform SHALL be capable of integrating with external services.

Initial important integrations include:

* WhatsApp.
* WordPress.
* Payment services when required.
* External service providers when required.

External integrations SHALL be treated as separate capabilities rather than embedded directly into core business concepts.

27.2 Why

The agency depends on external communication and content channels.

Keeping integrations separated allows them to evolve without destabilizing the reservation domain.

⸻

28. Operational Model

28.1 What

The system SHALL support a human-in-the-loop operational model.

Automation SHALL assist operators but SHALL NOT assume that external availability is correct unless explicitly verified.

The operator SHALL remain capable of reviewing and modifying commercial operations.

28.2 Why

The business depends on external providers whose real-time availability may not initially be accessible through APIs.

The system must therefore improve the existing human process rather than pretend that the business is fully automatable.

⸻

29. Source of Truth

29.1 What

The platform SHALL maintain a structured source of truth for:

* Products.
* Customers.
* Quotations.
* Pre-Reservations.
* Reservations.
* Availability verification.
* User activity.

WhatsApp conversations SHALL NOT be considered the authoritative business record.

29.2 Why

Communication channels are transient.

The agency needs durable structured information that can be searched, audited, reported, and reused.

⸻

30. MVP Scope

30.1 Included

The MVP SHALL prioritize:

* Product management.
* Experience management.
* Accommodation management.
* Categories.
* Add-ons.
* Packages.
* Configurable pricing.
* Customer requests.
* Pre-Reservations.
* Availability verification.
* Quotations.
* Reservations.
* Internal users.
* Simple roles and permissions.
* Auditability of important operations.
* Basic reports and statistics.
* Web customer channel.
* WhatsApp customer channel.
* WordPress content integration.
* Authentication.
* Privacy-aware customer data management.
* Tenant-aware domain design.

30.2 Why

These capabilities represent the minimum coherent business system required to replace the agency’s current fragmented reservation process.

⸻

31. Explicitly Deferred

The following capabilities SHALL NOT be required for the initial MVP unless separately approved:

* Fully automated availability verification.
* Complex dynamic pricing engines.
* Advanced role customization.
* Complex subscription management.
* Full SaaS billing.
* Multiple tenant administration.
* Advanced payment orchestration.
* Microservices architecture.
* AI autonomous reservation confirmation.
* Complex workflow engines.

Why

These capabilities may be valuable later, but introducing them prematurely would increase complexity before the core reservation process has been validated.

⸻

32. Core Business Principles

The platform SHALL follow these fundamental business principles:

Principle 1 — A request is not a reservation.

A customer’s intention must not be confused with a confirmed commercial commitment.

Principle 2 — Availability must be verified when required.

The existence of a product does not guarantee real-world availability.

Principle 3 — Products are customizable.

The platform must support both predefined offerings and customer-specific configurations.

Principle 4 — The operator remains in control.

Automation should assist the operator without hiding important business decisions.

Principle 5 — Business information must be structured.

WhatsApp and other communication channels are interfaces, not sources of truth.

Principle 6 — The system must be auditable.

Important commercial actions must be traceable.

Principle 7 — Simplicity comes first.

The MVP should solve the core business problem without implementing future complexity prematurely.

⸻

33. Success Criteria

The product SHALL be considered successful when the agency can manage the principal reservation lifecycle through the platform without reconstructing the operation manually from multiple disconnected systems.

At minimum, the agency should be able to:

1. Define what it sells.
2. Define how it is categorized.
3. Define what can be added.
4. Define and modify prices.
5. Receive a customer request.
6. Create a Pre-Reservation.
7. Verify availability.
8. Prepare or modify a quotation.
9. Confirm a reservation.
10. Maintain customer information.
11. Know who performed important actions.
12. Understand basic business performance.

The primary measure of success is not the number of technical features.

The primary measure is the degree to which the platform transforms the agency’s reservation operation into a structured, reliable, and traceable process.

⸻

34. Specification Boundary

This document intentionally defines WHAT the platform must accomplish and WHY those capabilities exist.

It does not prescribe:

* Database schemas.
* Angular components.
* API endpoints.
* Folder structures.
* Specific implementation algorithms.
* Infrastructure topology.
* Exact deployment configuration.

Those decisions SHALL be addressed by subsequent specifications and architecture documents.

The implementation SHALL derive from this specification rather than redefine the business requirements.

⸻

Final Product Definition

The platform is a tourism commerce and reservation system that transforms fragmented customer interactions and manual availability verification into a structured lifecycle:

Discover → Request → Pre-Reserve → Verify → Quote → Confirm → Reserve → Analyze

The system preserves human control where the business requires it while creating the foundations for future automation, scalability, and SaaS evolution.

The product’s fundamental purpose is:

Turn a tourism agency’s fragmented reservation operation into a structured, customizable, auditable, and scalable commercial process.