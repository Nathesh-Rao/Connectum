# Reference screenshots

Prototype at http://localhost:8443, headless Chrome, 390x844 viewport, deviceScaleFactor 2 (images are 780x1688). Each PNG is cropped to the `.phone` element.
At a viewport <= 480px wide the studio chrome is hidden and the phone is full-bleed (no 7px border / rounded frame). Status bar 9:41 and home indicator are drawn inside the screenshot.
Sample text is placeholder data only (email alex@example.com, code 482916).

- `01-splash.png` - Splash: white screen, centred logo, faint ambient disc/orbit. Source: src/screens/Splash.tsx, src/components/Ambient.tsx, .splash in src/index.css
- `02-onboarding-1-conversations.png` - Onboarding slide 1: constellation art, 'All your conversations in one place'. Source: src/screens/Onboarding.tsx, src/components/onboarding/ConstellationArt.tsx
- `03-onboarding-2-enterprises.png` - Onboarding slide 2: enterprises art, 'Work across multiple enterprises'. Source: src/screens/Onboarding.tsx, src/components/onboarding/EnterprisesArt.tsx
- `04-onboarding-3-security.png` - Onboarding slide 3: security art, 'Secure, simple and ready to go'. Source: src/screens/Onboarding.tsx, src/components/onboarding/SecurityArt.tsx
- `05-auth-sign-in.png` - Authentication, Sign In mode (default). Source: src/screens/Authentication.tsx, src/components/AccessForm.tsx
- `06-auth-set-up.png` - Authentication, Set Up mode. Source: src/components/AccessForm.tsx
- `07-auth-self-register.png` - Authentication, Self Register mode. Source: src/components/AccessForm.tsx
- `08-verification-empty.png` - Verification, six empty code cells ('Send again in 8s' captured ~1.5s after mount). Source: src/screens/Verification.tsx, src/components/AccessForm.tsx
- `09-verification-filled.png` - Verification, all six digits entered. Source: src/components/AccessForm.tsx
- `10-enterprises.png` - Enterprises list (Agile Labs marked current), Connectum ID strip, join row. Source: src/screens/Enterprises.tsx
- `11-enterprises-join-step1.png` - Join sheet, step 1: enterprise code input. Source: src/components/Sheet.tsx ('Join another enterprise')
- `12-enterprises-join-step2.png` - Join sheet, step 2: confirm joining Agile Labs. Source: src/components/Sheet.tsx ('Join Agile Labs')
- `13-enterprises-account-sheet.png` - Account options sheet: Set a password / Sign out. Source: src/components/Sheet.tsx ('Account options')
- `14-chats-home.png` - Chats home: enterprise header, search, filters, pinned workspace, conversation list, bottom nav. Source: src/screens/Chats.tsx, src/components/BottomNav.tsx
- `15-chats-new-chat-sheet.png` - New Group / Chat sheet. Source: src/components/Sheet.tsx ('New Group / Chat')
- `16-chats-enterprise-switcher-sheet.png` - Enterprise switcher sheet. Source: src/components/Sheet.tsx ('Enterprises')
- `17-notifications.png` - Notifications screen. Source: src/screens/Notifications.tsx
- `18-conversation-bottom.png` - Conversation with Priya Sharma, scrolled to the bottom (latest messages). Source: src/screens/Conversation.tsx, src/components/conversation/ThreadView.tsx
- `19-conversation-sent-form-card.png` - Conversation: a SENT form card (#1040, mine, has edit pencil in the dark strip), plus message bubbles. Source: src/components/FormCard.tsx (.sub-card.sent), src/components/conversation/ThreadView.tsx
- `20-conversation-received-form-card.png` - Conversation: a RECEIVED form card (#1042, read-only, no edit pencil) with incoming bubble and 'typing' row. Source: src/components/FormCard.tsx (.sub-card.received)
- `21-forms-picker-sheet.png` - Forms picker sheet: search, Recent chips, All forms list, My Submissions. Source: src/components/sheets/FormsPicker.tsx
- `22-form-screen-empty.png` - Form screen (Clinical examination - Ortho), untouched, defaults only. Source: src/components/FormScreen.tsx
- `23-form-screen-errors.png` - Same form after tapping Done with required fields empty: red 'This field is required' errors. Source: src/components/FormScreen.tsx
- `24-commands-sheet.png` - Commands sheet opened by typing '#' in the composer. Source: src/components/Sheet.tsx ('Commands'), src/screens/Conversation.tsx
- `25-summarise-60.png` - Summarise panel at its resting 60% height: chips, scope hint, ask input. Source: src/components/conversation/SummaryPanel.tsx
- `26-summarise-full.png` - Summarise panel dragged to full (94%) height. Source: src/components/conversation/SummaryPanel.tsx
- `27-ai-agents-empty.png` - AI Agents tab, empty state with suggestions. Source: src/screens/AiAgents.tsx, src/components/ai/AiEmpty.tsx, AiHeader.tsx, AiComposer.tsx
- `28-ai-agents-conversation.png` - AI Agents tab mid-conversation (question sent, answer streaming/just arrived). Source: src/components/ai/AiThread.tsx
- `29-submissions-list.png` - My Submissions list with filter chips and cards. Source: src/screens/Submissions.tsx, src/components/SubmissionsLayout.tsx
- `30-submission-detail.png` - Submission detail. Source: src/screens/SubmissionDetail.tsx, src/components/SubmissionsLayout.tsx
- `31-profile.png` - Profile tab. Source: src/screens/Profile.tsx
- `32-sign-out-sheet.png` - Sign-out confirmation sheet. Source: src/components/Sheet.tsx ('Sign out')
- `33-chats-filter-direct-teams.png` - Chats home with the 'Direct & Teams' filter selected. Source: src/screens/Chats.tsx, src/components/FilterChips.tsx
- `34-chats-search-typed.png` - Chats: search focused with 'pri' typed, list filtered to matches. Source: src/screens/Chats.tsx
- `35-chats-search-no-results.png` - Chats: search with no match ('No conversations found.') - the only empty state Chats has. Source: src/screens/Chats.tsx
- `36-conversation-sent-form-card-expanded.png` - Conversation: the sent card expanded with 'Show less' (extra fields revealed). Source: src/components/FormCard.tsx
- `37-summarise-full-answer.png` - Summarise panel at full height with a finished answer (Copy / Pin to chat actions). Source: src/components/conversation/SummaryPanel.tsx
- `38-summarise-60-answer.png` - Summarise panel back at 60% with the answer. Source: src/components/conversation/SummaryPanel.tsx
- `39-conversation-pinned-summary.png` - Conversation with a pinned summary card under the header (expanded). Source: src/components/conversation/PinnedSummary.tsx
- `40-conversation-pinned-summary-collapsed.png` - Pinned summary folded to its title row. Source: src/components/conversation/PinnedSummary.tsx
- `41-ai-model-sheet.png` - AI model picker sheet (Auto / Fast / Thinking). Source: src/components/sheets/AiSheets.tsx (AiModel)
- `42-ai-history-sheet.png` - AI history sheet (search past chats, list). Source: src/components/sheets/AiSheets.tsx (AiHistory)
