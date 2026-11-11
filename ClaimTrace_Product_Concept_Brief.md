# ClaimTrace — Product Concept Brief

**Document purpose:** Explain the ClaimTrace idea to another AI, designer, researcher, or developer so they can independently understand the problem, target users, intended solution, scope, assumptions, and validation needs.

**Status:** Early-stage concept. The problem area has supporting evidence, but the specific product and its proposed benefit still require user validation.

**Working name:** ClaimTrace  
**One-line description:** A private, claim-specific evidence tracker that helps Indian families organise health-insurance claim documents, record what they submitted and when, identify repeated document requests, and prepare a clear evidence-backed response.

---

## 1. Executive summary

ClaimTrace is intended for people managing a health-insurance claim for themselves or a family member—especially an adult child or caregiver helping a parent during or after hospitalisation.

Health-insurance claims can involve many documents, hospital bills, discharge summaries, diagnostic reports, payment proofs, insurer emails, deficiency letters, portal uploads, follow-up calls, and acknowledgements. The person coordinating the claim may be doing this while a relative is ill, while dealing with hospital discharge, or while trying to return to everyday responsibilities.

A recurring frustration described in public discussions is that an insurer may request documents again, issue queries whose meaning is unclear, or ask for material the family believes it has already provided. The family then has to reconstruct what was sent, when it was sent, through which channel, and whether there is proof that it was received. Documents may be scattered across a phone's Photos app, messaging conversations, email, downloads, paper files, and insurer portals.

ClaimTrace would give the family one organised, chronological record for a single claim. It would help the user collect relevant documents, record each submission and its supporting acknowledgement, capture new insurer requests, match those requests against existing records, and prepare a factual timeline or evidence packet when a follow-up is needed.

The core promise is:

> **When an insurer asks for a document again, help the family answer: “Did we already send this, when did we send it, and what evidence do we have?”**

ClaimTrace is not intended to decide whether a claim is valid, promise claim approval, automatically file insurance claims, impersonate an insurer, or replace the official complaint process. It is an evidence-management and claim-organisation tool that supports the user's interaction with existing insurers and grievance channels.

---

## 2. The problem

### 2.1 The situation ClaimTrace is designed for

A family member is hospitalised. Someone in the family becomes responsible for coordinating the insurance claim, often without prior experience. They may need to gather documents from the hospital, communicate with the insurer or third-party administrator (TPA), submit files through different channels, answer deficiency queries, and keep track of what has already happened.

As the process continues, it becomes difficult to maintain a reliable history:

- Which documents were requested?
- Which documents have been collected from the hospital?
- Which files were actually submitted to the insurer?
- When, how, and to which channel were they submitted?
- Is there an upload receipt, email acknowledgement, portal screenshot, or other evidence of submission?
- Has the insurer acknowledged receipt, marked the document as verified, or merely shown the claim as under process?
- Is a new request asking for a genuinely new item, a different version of an existing item, or something that appears to have been submitted already?
- What did the insurer ask for previously, and what response did the family give?
- If the matter needs escalation, can the family present a concise and accurate chronology instead of searching through old messages and attachments?

The user is not necessarily missing the documents themselves. The gap may be the absence of a trustworthy, consolidated record of the document-request and submission history.

### 2.2 Why the circumstances make this worse

- The family may be emotionally stressed because someone is ill or recovering.
- Hospitalisation and discharge can create urgent, time-sensitive administrative pressure.
- The person handling the claim may have a full-time job, studies, or caregiving responsibilities.
- Medical paperwork can be extensive, technical, repetitive, and inconsistent in naming.
- Different documents may be stored in paper folders, email, messaging apps, phone galleries, cloud drives, and insurer portals.
- A portal can fail, an upload may not complete, a file may exceed a size limit, or an acknowledgement may be difficult to find later.
- A repeated request can be confusing: a similarly named document might be a duplicate, a different period's report, a missing page, a clearer scan, or a genuinely different requirement.
- A family may not understand whether the insurer has received a file, accepted it as sufficient, verified it, or simply acknowledged the upload.

ClaimTrace must therefore avoid collapsing these separate states into a single misleading status such as “submitted.”

### 2.3 The specific problem to target first

The narrowest and clearest initial problem is **keeping track of what was requested, what was submitted, and what proof of submission exists during a health-insurance claim**.

The app is not initially trying to solve the entire health-insurance system, policy interpretation, unfair rejection, claim adjudication, or hospital billing. It focuses on a concrete administrative failure that families may be able to improve with better evidence organisation.

---

## 3. Who ClaimTrace helps

### Primary user

**A family member or caregiver coordinating a health-insurance claim for a patient.** This may be an adult child managing the claim for a parent, a spouse supporting a partner, or another relative helping someone through hospitalisation and reimbursement.

The person handling the claim may not be the policyholder or the patient. They are often the person collecting documents, sending emails, following up, and trying to understand what remains outstanding.

### Secondary users

- A policyholder handling their own hospitalisation claim.
- A person submitting a reimbursement claim after paying hospital expenses.
- A family handling several claim-related documents or more than one query cycle.
- A trusted helper who assists an older adult or a less digitally confident family member.
- Potentially, a patient advocate who helps a family organise claim correspondence, provided the patient authorises sharing of the sensitive records.

### Initial geography and context

The first intended context is **India**, where health-insurance claim coordination can involve a hospital, insurer, TPA, online portals, email, phone calls, and formal grievance channels. The product should not assume that every insurer uses the same process or that all documents can be submitted through a single digital interface.

### Who it is not primarily for at first

- Insurance companies managing claims at scale.
- Hospital billing departments.
- Insurance agents managing a large portfolio of policyholders.
- Lawyers or professional claims consultants requiring a full case-management system.

Those may be separate future directions, but they should not distract from the first use case: an individual or family trying to stay organised during one claim.

---

## 4. What ClaimTrace does

ClaimTrace maintains a claim-specific evidence ledger: a chronological record connecting requests, documents, submission events, acknowledgements, and follow-up actions.

The intended capabilities are:

1. **Create a claim record.** The user creates a private workspace for one health-insurance claim and records basic identifying context, such as a nickname for the claim, insurer, claim/reference number if available, patient relationship, and key dates. Avoid collecting data that is not needed.

2. **Collect and organise documents.** The user imports or scans relevant records such as hospital bills, discharge summaries, prescriptions where relevant, diagnostic reports, payment proofs, insurer letters, and email or portal acknowledgements. Documents should remain associated with the particular claim.

3. **Record document requests.** When the insurer or TPA asks for information, the user records or imports the request. ClaimTrace helps turn the request into a checklist of requested items, while making clear that the interpretation may need user confirmation.

4. **Record submission events.** The user logs what was sent, the date and approximate time, the channel used (for example, insurer portal, email, physical submission, or another channel), and any supporting proof. The app should distinguish a user's assertion that something was sent from independently supported evidence that it was sent or acknowledged.

5. **Track evidence states accurately.** A document might be collected, ready to submit, reported as submitted, accompanied by a submission receipt, acknowledged as received, marked verified by the insurer, or still unresolved. Those states must not be treated as interchangeable.

6. **Match a new request against prior records.** If a new letter or message requests a discharge summary, the app checks whether a similar item is already in the claim archive and whether a submission event or acknowledgement exists. It then shows the matching evidence for the user to inspect. A match is a suggestion, not proof that the insurer has accepted the document as sufficient.

7. **Flag possible repeated requests.** If a new request appears to repeat an earlier one, show the earlier request, the associated document, the recorded submission event, and any receipt or acknowledgement. Let the user confirm whether it is truly a repeat. Do not automatically accuse the insurer of error or bad faith.

8. **Maintain a claim timeline.** Show key events in chronological order: request received, document collected, response prepared, submission recorded, acknowledgement received, follow-up made, status changed, or escalation filed.

9. **Prepare an evidence packet.** Compile a selected set of documents and a neutral timeline that the user can review and then share through an existing, official channel. The packet should distinguish confirmed facts, user-entered information, and unconfirmed events.

10. **Explain available next steps.** Provide general, carefully maintained signposting to the insurer's grievance officer, IRDAI's Bima Bharosa portal, or other official channels when appropriate. The app should not present itself as an insurer, regulator, or legal adviser.

---

## 5. Example user journey

A parent undergoes a procedure and the family submits a reimbursement claim.

1. The adult child creates a ClaimTrace record for the claim.
2. They scan or import the hospital bill, discharge summary, relevant reports, and the claim submission acknowledgement.
3. The insurer sends a request for additional information. The child imports the letter or records its contents.
4. ClaimTrace identifies the requested document names and asks the user to confirm the interpretation.
5. The app finds a possible matching discharge summary in the archive, plus a record showing that it was uploaded on an earlier date. A saved acknowledgement or portal receipt is associated with the event.
6. The app displays the earlier submission and the evidence supporting it. It explains that the record appears to match, but the user should confirm whether the new request could require a different version, additional page, or different date range.
7. The user reviews the evidence, decides how to respond, and uses the insurer's existing official channel. ClaimTrace does not send a claim response automatically.
8. The user records the new response and any acknowledgement in the timeline.
9. If the matter remains unresolved and the user chooses to escalate, ClaimTrace can assemble a concise chronology and selected supporting records for use through the insurer's grievance process or the relevant official channel.

This example is illustrative. The app should support the possibility that the insurer's new request is legitimate and different from the earlier one.

---

## 6. The core insight and value proposition

### Core insight

A folder of documents is not enough. A family also needs a reliable history of **which item was requested, which version was sent, when and how it was sent, and what acknowledgement or receipt exists**.

### Value proposition

ClaimTrace helps a family transform scattered claim paperwork into a reviewable evidence history, so it can answer document-related queries with less searching, less repeated manual work, and better-organised supporting evidence.

### What makes it distinct from a generic document scanner or notes app

A normal scanner stores files. A notes app can record reminders. A folder can keep PDFs together. ClaimTrace's intended distinction is the relationship between:

- the insurer's request,
- the document that may satisfy that request,
- the specific submission event,
- proof or acknowledgement associated with that submission,
- later requests and responses,
- and the chronological record of the claim.

The central feature is therefore not scanning or document storage by itself. It is the **request-to-document-to-submission-evidence chain**.

### A critical limitation

ClaimTrace can help establish what the user recorded and what the available receipts appear to demonstrate. It cannot prove that the insurer's internal system received or accepted a document unless the relevant evidence supports that conclusion. A locally saved file or screenshot alone may not prove successful submission.

---

## 7. How Apple products can make the experience better

The idea is intended to be a native Apple-platform experience, especially for the Swift Student Challenge. Apple technology should help with the actual claim workflow rather than being added as decoration.

- **iPhone camera and document scanning:** Make it easier to capture paper bills, letters, acknowledgements, and receipts without needing a separate scanner.
- **On-device text recognition:** Recognise text in supported documents and screenshots so the user can search documents and compare new requests with records already stored.
- **Native document handling and sharing:** Let the user review selected evidence and deliberately share a report or PDF through the channel they choose.
- **Accessibility:** Support large readable text, VoiceOver, clear language, and a step-by-step workflow suited to a stressful situation.
- **Local-first operation:** The core demonstration can work offline using sample documents. Sensitive health information should not be uploaded to a service by default merely to make the prototype work.

The Apple device's contribution is that it acts as a portable document scanner and private claim-workspace. The user could be helping a relative whose claim is handled on another device or through a web portal; ClaimTrace need not be installed on the patient's phone.

This is not an assertion that only Apple devices can provide these capabilities. The product should be native to Apple platforms for the competition, while its distinctive value comes from the evidence workflow rather than exclusivity to a device brand.

---

## 8. What the first version should include

The first version should be narrowly scoped around a single reimbursement claim and the repeated-document-request scenario.

### Essential first-version scope

- One claim workspace.
- Importing or scanning sample documents.
- Organising documents by understandable types and dates.
- Recording insurer requests and requested items.
- Recording a submission event with date, channel, and supporting evidence where available.
- Distinguishing claimed submission from acknowledged receipt or verified status.
- Matching a new request with possible existing documents and submission records.
- Highlighting possible repeated requests while requiring user confirmation.
- A chronological claim timeline.
- A user-reviewed export containing selected documents and a factual chronology.
- Clear privacy language and the ability to remove the claim record and its local data.
- An offline demonstration using fictional documents and no live insurer integration.

### What can be simulated for a competition demo

For a first proof of concept, the app can use a small set of realistic but entirely fictional documents: a discharge summary, a hospital invoice, an insurer query letter, a submission acknowledgement, and a second request that appears to ask for the same document. The demo should show how the app connects the request to the earlier submission evidence.

The sample scenario must not use real patient information, real policy numbers, real claim numbers, or real medical documents without explicit permission and appropriate safeguards.

### Not required for the first version

- Direct integration with insurers' systems.
- Automatic login to insurer portals.
- Automatic claim filing or automatic reply-sending.
- Predicting the insurer's decision.
- Legal interpretation of insurance contracts.
- Automated judgements about whether a rejection is lawful.
- A generic AI chatbot for all insurance questions.
- A social network, public ranking of insurers, or public posting of claim details.
- A large cloud database of patients' medical records.
- A promise that using the app will lead to claim approval or faster settlement.

---

## 9. Privacy, trust, and safety requirements

ClaimTrace would handle highly sensitive medical, financial, and identity-related information. Privacy is a core product requirement, not an optional enhancement.

- Prefer local storage for the first version and offline competition demo.
- Do not require bank credentials, UPI PINs, passwords, OTPs, or insurer account credentials.
- Do not collect medical or identity information that is not essential to the user's chosen workflow.
- Make it clear when information is being imported, stored, exported, or shared.
- Require deliberate user action before sharing an evidence packet.
- Avoid sending medical documents to a remote AI service by default.
- Clearly label the source and confidence of each record: scanned text, user-entered detail, submission claim, upload receipt, or insurer acknowledgement.
- Allow the user to inspect and correct extracted text before it affects the timeline or a report.
- Never silently alter an original document. If notes, annotations, or redactions are added, preserve the original or make the change clear.
- Support appropriate deletion of local records and explain what deletion does and does not remove from any exported or separately shared files.
- Use fictitious data in the demo.
- Avoid fear-based language or claims that the insurer is acting improperly merely because a request appears repeated.

Medical records are especially sensitive. A future version would require a careful security and privacy review before being used with real claims at scale.

---

## 10. What ClaimTrace must not claim or do

To preserve trust, ClaimTrace must not:

- Promise that a claim will be approved, paid, or resolved faster.
- Tell users that a document was received when the app only knows that the user selected or scanned it.
- Treat “uploaded,” “received,” “verified,” “sufficient,” and “approved” as equivalent statuses.
- Assert that the insurer is at fault based only on a possible document match.
- Automatically resubmit private medical documents to an insurer.
- Automatically file a complaint, initiate legal action, or send a confrontational email.
- Determine policy coverage or make final legal conclusions about whether a rejection is valid.
- Substitute its own instructions for official grievance procedures.
- Encourage users to expose unredacted medical or policy information publicly to seek help.

The product's job is to help the user organise facts, maintain a history, and make informed decisions about the next step.

---

## 11. Evidence that the problem exists

The following public sources support the broader problem of health-insurance claim friction and the narrower anecdotal pattern of repeated document requests. They do **not** prove that ClaimTrace itself will work or that repeated document requests are the cause of every delayed or rejected claim.

### A. Survey findings and industry scale

1. **LocalCircles, 3 May 2024 — general insurance survey.** The survey reports that 43% of surveyed policyholders who had filed a health-insurance claim in the previous three years had difficulties getting it processed. Challenges reported included rejection, partial approval, and long processing times. The survey received over 39,000 responses from citizens in 302 districts; the exact question-level response counts and survey methodology should be read on the source page before treating the percentage as nationally representative.
   - Source: https://www.localcircles.com/a/press/page/general-insurance-survey
   - Independent report: https://indianexpress.com/article/business/43-consumers-faced-problems-in-health-insurance-claims-localcircles-survey-9304406/

2. **LocalCircles, 7 March 2026 — health-insurance claim survey.** Reports that during FY2024 insurers registered over 3 crore health-insurance claims worth approximately ₹1.2 lakh crore, based on IRDAI and industry data, and describes continuing friction in claim processing. This is context for the scale of the process; it is not a count of potential ClaimTrace users or of repeated-document cases.
   - Source: https://www.localcircles.com/a/press/page/health-insurance-claim-survey

3. **Parliamentary answer on complaints relating to health-insurance claims, March 2026.** Reports 47,658 complaints for FY2023–24, 64,365 for FY2024–25, and 73,729 for FY2025–26 up to February 2026 registered on IRDAI's Bima Bharosa portal for various reasons related to health-insurance claims. These are broader complaints, not complaints exclusively about duplicate document requests.
   - Public report: https://policyindex.ai/in/gazette/parliament-question-rejection-of-claims-by-health-insurance-companies-a49gj8
   - News report: https://cafemutual.com/news/industry/37363-health-insurance-complaints-hit-73729-in-fy26-so-far-govt

### B. Public first-person accounts

These Reddit posts describe experiences similar to the workflow ClaimTrace intends to improve. They are anecdotes, may be incomplete or disputed, and must not be treated as representative statistics or verified findings about a specific insurer.

1. **“Reimbursement Claim” — r/indiahealthinsurance, April 2026.** The author describes repeated requests for documents over more than 30 days, including items they believed had already been provided, and describes escalating the issue. Useful because it directly illustrates the confusion around repeated requests and the need to track past responses.
   - https://www.reddit.com/r/indiahealthinsurance/comments/1shuj0n/reimbursement_claim/

2. **“Advice related to claim processing” — r/indiahealthinsurance, September 2026.** The author describes resubmitting documents, portal upload failures, email size limits, repeated queries, and difficulty progressing through grievance channels. Useful as an example of evidence distributed across several channels and technical points of failure.
   - https://www.reddit.com/r/indiahealthinsurance/comments/1wgp972/advice_related_to_claim_processing/

3. **“Insurance company keeps asking for more documents after approving most of the claim amount” — r/indiahealthinsurance, June 2026.** The author asks about requests for additional medical and payment records, whether the hospital should provide them, and whether the insurer can review requirements together. Useful for understanding the stress and uncertainty created by complex document requests.
   - https://www.reddit.com/r/indiahealthinsurance/comments/1tve751/insurance_company_keeps_asking_for_more_documents/

4. **“Care Health rejected my mother's ₹1.9L claim because the hospital called the document ‘Inpatient Case Sheet’ instead of ‘Indoor Case Papers’” — r/indiahealthinsurance, October 2026.** An anecdotal account of terminology differences, document resubmission, and a mismatch between a hospital's document title and an insurer's requested title. Useful as a related problem for future investigation: different names may refer to the same or similar records, but the app must not assume equivalence without confirmation.
   - https://www.reddit.com/r/indiahealthinsurance/comments/1wwxlde/care_health_rejected_my_mothers_19l_claim_because/

### C. Official grievance guidance

**IRDAI Bima Bharosa FAQ.** Provides official instructions for raising an insurance grievance, including approaching the insurer's grievance redressal officer, maintaining written acknowledgement, and escalating through Bima Bharosa when appropriate. ClaimTrace should signpost users to official routes, not replace them.
- https://bimabharosa.irdai.gov.in/Home/FAQ
- Bima Bharosa portal: https://bimabharosa.irdai.gov.in/

### D. Apple's relevant platform capability

Apple's document scanning and text-recognition capabilities can support the capture and organisation of paper documents and screenshots. These capabilities support feasibility; they do not in themselves prove user demand.
- VisionKit: https://developer.apple.com/documentation/visionkit
- Vision: https://developer.apple.com/documentation/vision

### Research limitations

- Quora and Facebook content was not reliably accessible in the research environment used for this concept brief. This document does not claim to represent a comprehensive analysis of those platforms or private groups.
- Public posts are self-selected and often concern particularly difficult experiences; they cannot establish the overall prevalence of repeated-document requests.
- Survey findings establish wider claim-processing friction, but not necessarily the exact failure mode ClaimTrace is designed to solve.
- All cited web sources and regulatory instructions should be rechecked before use in a final competition submission because facts, portals, deadlines, and rules may change.

---

## 12. Key assumptions that must be validated

The concept should not proceed directly to full implementation without testing these assumptions with people who have handled real health-insurance claims.

1. **Frequency:** Repeated or confusing document requests happen often enough to be a meaningful user problem, rather than an uncommon edge case.
2. **Severity:** The lack of a consolidated submission history causes substantial confusion, extra work, delays in responding, or difficulty escalating.
3. **Evidence availability:** Users can obtain and retain useful submission receipts, emails, portal acknowledgements, or screenshots. If they often cannot, the product must be honest about the limits of proving submission.
4. **Matching quality:** Requests and documents can be matched usefully even when titles differ, without dangerous false matches.
5. **User adoption:** People will use a separate app while managing a stressful claim instead of relying entirely on email, WhatsApp, paper folders, or a phone's Files/Photos apps.
6. **Apple-device relevance:** A native iPhone workflow is useful to the person coordinating the claim, including when the patient and their insurer interact through another device or portal.
7. **Privacy trust:** Users are comfortable scanning and storing medical claims material in the app if the privacy behaviour is clear and local-first.
8. **Outcome improvement:** The app helps users find past submission evidence and prepare a factual chronology more quickly or accurately than their existing method.

### Recommended validation exercise

Interview 5–10 people who recently managed a health-insurance claim for themselves or a family member. Include both people whose claims were straightforward and people who experienced repeated queries, partial approval, or delays.

Ask them to reconstruct one claim using their actual workflow (with sensitive information hidden or redacted):

- What documents were requested?
- How did they keep track of what had been collected and submitted?
- Did the insurer ask for anything again?
- How did they establish whether it had already been submitted?
- Where were the relevant receipts or acknowledgements stored?
- What was the most frustrating administrative step?
- What did they do when the claim remained unresolved?
- Would a record connecting each request to the document, submission event, and receipt have changed what they did?

Do not merely ask whether they like the idea. Observe whether the proposed workflow solves a real task. A useful prototype test is to give participants a fictional claim folder containing a previous submission receipt and a new, repeated-looking request, then measure whether they can identify the relationship and prepare an accurate chronology without help.

---

## 13. How success should be measured

The idea should be evaluated on task outcomes, not just visual appeal or the number of features.

Possible early success measures:

- A user can find the prior submission associated with a repeated-looking request.
- A user can distinguish a document that is merely scanned from one with a recorded submission event and one with an acknowledgement.
- A user can assemble a chronological evidence packet without manually searching across multiple folders and conversations.
- The app avoids false claims that a document was received, verified, or accepted.
- A user can understand the next step without the app making legal conclusions or promising an outcome.
- Users report that the chronology and evidence links are meaningfully better than their existing process.

For the Swift Student Challenge prototype, the core demonstration should prove one coherent task end to end: a new request arrives, the app finds a possible match in the archive, the user reviews the earlier submission evidence, and the app generates a clear chronology. It is better to demonstrate this accurately than to show many unfinished insurance features.

---

## 14. Main risks and responses

### Risk: The problem is real, but the proposed tool is not useful enough

People may already manage this adequately through email and folders, or repeated requests may be driven by legitimate requirements rather than poor evidence organisation.

**Response:** Validate with recent claimants before implementation. Focus on whether the user can complete the evidence-retrieval task better than before.

### Risk: False document matches

Two files may have similar titles but cover different treatment periods, contain different pages, or be different document types.

**Response:** Present matches as suggestions; show the original request and candidate document side by side conceptually; require confirmation; never automatically tell the user that a request is redundant.

### Risk: Misrepresenting the proof of submission

A screenshot of a file or a note saying “sent” may not establish that the insurer received or accepted it.

**Response:** Track provenance and state explicitly. Separate “document exists,” “user recorded submission,” “submission receipt saved,” “receipt/acknowledgement indicates received,” “insurer marked verified,” and “claim approved.” Use only the strongest status supported by evidence.

### Risk: Sensitive health data exposure

Medical records can contain highly sensitive health and identity information.

**Response:** Start local-first, minimise collected information, require explicit sharing, use fictional data for demos, and undertake security/privacy review before broad real-world deployment.

### Risk: The app seems to accuse insurers of wrongdoing

Repeated-looking requests are not always errors; the insurer may need a clearer scan, additional page, different date range, or a legally required item.

**Response:** Use neutral language such as “possible match” or “similar prior request.” Let the user check the context and decide how to respond.

### Risk: Scope expands into a full insurance platform

Direct insurer integrations, policy interpretation, grievance filing, claim prediction, and general AI assistance could overwhelm the initial concept.

**Response:** Keep the first version focused on the evidence ledger and the repeated-document-request workflow.

---

## 15. Fit for the Apple Swift Student Challenge

ClaimTrace is a candidate for a short, offline-capable native experience because the problem can be demonstrated through a small but complete scenario. The concept can showcase document capture, text recognition, record matching, careful information hierarchy, accessibility, and data provenance without requiring a live insurer integration.

The project should be built around the challenge's then-current official submission rules. Apple's rules and submission dates can change by year; verify the edition's eligibility, file format, size restrictions, offline requirements, and interaction-duration requirements before committing to exact implementation details.

The demo should use invented policy details and entirely fictional medical records. It should never depend on access to a real person's insurance account or health information.

Official challenge page: https://developer.apple.com/swift-student-challenge/  
Eligibility page: https://developer.apple.com/swift-student-challenge/eligibility/

---

## 16. Product statement for another AI

When asked to continue developing ClaimTrace, treat it as:

> **A privacy-first evidence tracker for Indian health-insurance claims, designed primarily for family members and caregivers who coordinate claims. It connects each insurer request to relevant documents, recorded submission events, and any available receipts or acknowledgements. Its key use case is helping a user determine whether a repeated-looking document request corresponds to an item already submitted, then prepare an accurate, user-reviewed chronology and evidence packet. It does not decide claim validity, replace official grievance channels, or guarantee an insurer outcome.**

Maintain these principles when suggesting or designing features:

- Start from the confirmed user problem, not a desire to add AI.
- Keep the first version focused on one claim and one evidence workflow.
- Treat matching as assistance, not an authoritative decision.
- Preserve the distinction between collected, submitted, received, verified, and approved.
- Make privacy, user control, and clear provenance central to the product.
- Validate the exact workflow with real claimants before assuming the idea is a fit.
- Treat survey statistics, public posts, and official grievance counts as supporting context—not proof that this product will succeed.

---

## 17. Bottom line

ClaimTrace aims to solve a specific administrative problem during health-insurance claims: families often have to manage many documents and requests while under stress, and may struggle to reconstruct what was sent and what evidence exists when a request comes back.

Its proposed contribution is a single, chronological evidence trail that links the request, document, submission event, and available acknowledgement. The initial product should be small, private, honest about uncertainty, and useful even without insurer integrations.

The concept is promising enough to validate, but it is not yet proven. The next meaningful step is to observe how recent claimants actually organise documents and submission evidence, then test whether ClaimTrace improves that task.
