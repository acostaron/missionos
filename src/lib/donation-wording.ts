// Pass 9.32 (Ron 2026-10-21): events speak of donations, not payments. Server messages still say "payment" /
// "price" / "fee"; this rewrites them for display. Order matters (longer phrases first).
const RULES: [RegExp, string][] = [
  [/This is a paid event\. Check members in with Scan QR so payment is checked\./g,
    'This event has a suggested donation. Check members in with Scan QR so donations are checked.'],
  [/\bpayment reports?\b/gi, 'donation report'],
  [/\bPayments\b/g, 'Donations'],
  [/\bpayments\b/g, 'donations'],
  [/\bPayment\b/g, 'Donation'],
  [/\bpayment\b/g, 'donation'],
  [/\bpay at the event\b/g, 'give at the event'],
  [/\bpay by\b/g, 'give by'],
  [/has nothing to pay/g, 'has no donation pending'],
  [/how it was paid/g, 'how it was given'],
  [/\bguest price\b/g, 'guest donation'],
  [/\bregular price\b/g, 'regular donation'],
  [/\bearly-bird price\b/g, 'early-bird donation'],
  [/\bEnter prices\b/g, 'Enter amounts'],
  [/\bthe event fee\b/g, 'the suggested donation'],
  [/\bEnter a fee\b/g, 'Enter an amount'],
];

export function donationWording(text: string): string {
  return RULES.reduce((s, [re, to]) => s.replace(re, to), text);
}
