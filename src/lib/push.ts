// Push notifications on this device (Pass 9.34, Claude 2026-10-21). Web Push with the app's service worker.
// iPhone / iPad: only when MissionOS is added to the Home Screen and opened from there (iOS 16.4 or later).
import { supabase } from './supabase/client';

export type PushSupport = 'supported' | 'ios_needs_home_screen' | 'unsupported';

export function isIos(): boolean {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
}

export function isStandalone(): boolean {
  return window.matchMedia?.('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true;
}

export function pushSupport(): PushSupport {
  const hasApi = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  if (isIos() && !isStandalone()) return 'ios_needs_home_screen';
  return hasApi ? 'supported' : 'unsupported';
}

function urlBase64ToUint8Array(base64: string): Uint8Array<ArrayBuffer> {
  const padding = '='.repeat((4 - (base64.length % 4)) % 4);
  const raw = atob((base64 + padding).replace(/-/g, '+').replace(/_/g, '/'));
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function toBase64Url(buf: ArrayBuffer | null): string {
  if (!buf) return '';
  const bytes = new Uint8Array(buf);
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function publicKey(): Promise<string> {
  const base = import.meta.env.VITE_SUPABASE_URL as string;
  const res = await fetch(`${base}/functions/v1/send-reminders?push_public_key=1`);
  const out = (await res.json().catch(() => ({}))) as { public_key?: string | null };
  if (!out.public_key) throw new Error('Notifications are not set up yet. Please try again later.');
  return out.public_key;
}

export async function currentSubscription(): Promise<PushSubscription | null> {
  if (pushSupport() !== 'supported') return null;
  const reg = await navigator.serviceWorker.getRegistration();
  return reg ? reg.pushManager.getSubscription() : null;
}

function deviceLabel(): string {
  const ua = navigator.userAgent;
  const os = isIos() ? 'iPhone/iPad' : /Android/i.test(ua) ? 'Android' : /Mac/i.test(ua) ? 'Mac' : /Windows/i.test(ua) ? 'Windows' : 'Device';
  const br = /Edg\//.test(ua) ? 'Edge' : /Chrome\//.test(ua) ? 'Chrome' : /Firefox\//.test(ua) ? 'Firefox' : /Safari\//.test(ua) ? 'Safari' : '';
  return [os, br].filter(Boolean).join(' · ');
}

/** Asks permission (must be called from a tap), subscribes this device and saves it. */
export async function enablePush(orgId: string): Promise<void> {
  if (pushSupport() !== 'supported') throw new Error('Notifications are not available on this device.');
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') {
    throw new Error('Notifications are blocked for MissionOS. Allow them in your phone or browser settings, then try again.');
  }
  const reg = await navigator.serviceWorker.ready;
  let sub = await reg.pushManager.getSubscription();
  if (!sub) {
    sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: urlBase64ToUint8Array(await publicKey()) });
  }
  const { error } = await supabase.rpc('save_my_push_subscription', {
    p_organization_id: orgId,
    p_endpoint: sub.endpoint,
    p_p256dh: toBase64Url(sub.getKey('p256dh')),
    p_auth: toBase64Url(sub.getKey('auth')),
    p_device_label: deviceLabel(),
  });
  if (error) throw error;
}

export async function disablePush(orgId: string): Promise<void> {
  const sub = await currentSubscription();
  if (!sub) return;
  const { error } = await supabase.rpc('remove_my_push_subscription', { p_organization_id: orgId, p_endpoint: sub.endpoint });
  await sub.unsubscribe().catch(() => false);
  if (error) throw error;
}
