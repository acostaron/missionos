/* MissionOS push notifications (Pass 9.34, Claude 2026-10-21).
   Loaded by the generated service worker (workbox importScripts). Shows a reminder sent by the send-reminders
   edge function and opens My Events (or the given page) when it is tapped.
   Pass 9.35: tells the server the notification was shown / tapped (data.track), for the admin Activity page. */
function track(url, event) {
  if (!url) return Promise.resolve();
  return fetch(`${url}&t=${event}&src=push`, { mode: 'no-cors', cache: 'no-store' }).catch(() => undefined);
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { title: 'MissionOS', body: event.data ? event.data.text() : '' };
  }
  const title = data.title || 'MissionOS';
  event.waitUntil(
    Promise.all([
      self.registration.showNotification(title, {
        body: data.body || '',
        tag: data.tag || undefined,
        icon: '/icons/icon-192.png',
        badge: '/icons/icon-192.png',
        data: { url: data.url || '/app/my-events', track: data.track || null },
      }),
      track(data.track, 'open'),
    ]),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL((event.notification.data && event.notification.data.url) || '/app/my-events', self.location.origin).href;
  // open the app right away (inside the tap), and report the tap alongside
  const opened = self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
    for (const c of list) {
      if (c.url.startsWith(self.location.origin) && 'focus' in c) {
        c.navigate(target);
        return c.focus();
      }
    }
    return self.clients.openWindow(target);
  });
  event.waitUntil(Promise.all([opened, track(event.notification.data && event.notification.data.track, 'click')]));
});
