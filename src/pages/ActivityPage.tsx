// Activity (admins): what reminders went out on a day and who opened them, who opened the app, sign-ins
// (Pass 9.35, Ron 2026-10-21).
import { useMemo, useState } from 'react';
import { Activity, BellRing, ChevronLeft, ChevronRight, LogIn, Mail, Search, Smartphone } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { useActivityReport, type ActivityDelivery } from '../features/activity/api';
import { normalizeError } from '../lib/supabase/errors';
import { addDaysToDateStr, formatNyDateShort, formatNyTime, getTodayNyDate } from '../lib/ny-time';
import { Alert, Badge, Card, EmptyState, Input, PageHeader, Select, StatCard } from '../components/ui';

function when(iso: string | null): string {
  if (!iso) return '—';
  return `${formatNyDateShort(iso)} ${formatNyTime(iso)}`;
}

function ago(iso: string | null, today: string): string {
  if (!iso) return 'Never';
  const d = new Date(iso);
  const days = Math.floor((new Date(`${today}T12:00:00`).getTime() - d.getTime()) / 86_400_000);
  if (days <= 0) return `Today ${formatNyTime(iso)}`;
  if (days === 1) return 'Yesterday';
  return `${days} days ago`;
}

function DeliveryStatus({ d }: { d: ActivityDelivery }) {
  if (d.status === 'failed') return <Badge variant="danger">Failed</Badge>;
  if (d.status === 'claimed') return <Badge variant="neutral">Sending…</Badge>;
  const opened = d.channel === 'push' ? 'Shown' : 'Opened';
  const clicked = d.channel === 'push' ? 'Tapped' : 'Clicked';
  return (
    <span className="flex flex-wrap gap-1">
      <Badge variant="success">Sent</Badge>
      {d.clicked_at ? (
        <Badge variant="info">{clicked}</Badge>
      ) : d.opened_at ? (
        <Badge variant="info">{opened}</Badge>
      ) : (
        <Badge variant="neutral">Not {opened.toLowerCase()}</Badge>
      )}
    </span>
  );
}

export default function ActivityPage() {
  const { activeOrganization } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;
  const today = getTodayNyDate();
  const [day, setDay] = useState(today);
  const [channel, setChannel] = useState<'all' | 'email' | 'push'>('all');
  const [show, setShow] = useState<'all' | 'opened' | 'not_opened' | 'failed'>('all');
  const [q, setQ] = useState('');
  const { data, isLoading, error } = useActivityReport(orgId, day);

  const deliveries = useMemo(() => {
    const term = q.trim().toLowerCase();
    return (data?.deliveries ?? []).filter((d) => {
      if (channel !== 'all' && d.channel !== channel) return false;
      if (show === 'opened' && !(d.opened_at || d.clicked_at)) return false;
      if (show === 'not_opened' && (d.status !== 'sent' || d.opened_at || d.clicked_at)) return false;
      if (show === 'failed' && d.status !== 'failed') return false;
      if (term && !`${d.display_name} ${d.member_number ?? ''} ${d.item_title ?? ''} ${d.group_name ?? ''}`.toLowerCase().includes(term)) return false;
      return true;
    });
  }, [data, channel, show, q]);

  const stats = useMemo(() => {
    const all = data?.deliveries ?? [];
    const of = (c: string) => all.filter((d) => d.channel === c);
    const sent = (l: ActivityDelivery[]) => l.filter((d) => d.status === 'sent').length;
    const opened = (l: ActivityDelivery[]) => l.filter((d) => d.opened_at || d.clicked_at).length;
    const clicked = (l: ActivityDelivery[]) => l.filter((d) => d.clicked_at).length;
    const failed = all.filter((d) => d.status === 'failed').length;
    const accounts = data?.accounts ?? [];
    const week = addDaysToDateStr(today, -7);
    const recent = accounts.filter((a) => {
      const t = [a.last_sign_in_at, a.last_active_at].filter(Boolean).sort().pop();
      return t && t.slice(0, 10) >= week;
    }).length;
    return {
      email: of('email'), push: of('push'), sent, opened, clicked, failed,
      accounts: accounts.length, recent, never: accounts.filter((a) => !a.last_sign_in_at).length,
      devices: accounts.filter((a) => a.push_devices > 0).length,
    };
  }, [data, today]);

  const accountRows = useMemo(() => {
    const term = q.trim().toLowerCase();
    return (data?.accounts ?? []).filter((a) => !term || `${a.display_name} ${a.member_number ?? ''}`.toLowerCase().includes(term));
  }, [data, q]);

  if (error) {
    const e = normalizeError(error);
    return (
      <Alert variant="warning" title="Activity">
        {e.code === '42501' ? 'Only administrators can see the activity page.' : e.message}
      </Alert>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Activity"
        description="Reminders sent on a day and whether they were opened, who opened MissionOS, and member sign-ins."
      />

      <div className="flex flex-wrap items-center gap-2">
        <button type="button" aria-label="Previous day" className="rounded-md border border-line p-2 hover:bg-surface-muted" onClick={() => setDay(addDaysToDateStr(day, -1))}>
          <ChevronLeft className="h-4 w-4" />
        </button>
        <Input type="date" className="w-44" value={day} max={today} onChange={(e) => e.target.value && setDay(e.target.value)} />
        <button
          type="button"
          aria-label="Next day"
          disabled={day >= today}
          className="rounded-md border border-line p-2 hover:bg-surface-muted disabled:opacity-40"
          onClick={() => setDay(addDaysToDateStr(day, 1))}
        >
          <ChevronRight className="h-4 w-4" />
        </button>
        {day !== today && (
          <button type="button" className="text-sm text-primary hover:underline" onClick={() => setDay(today)}>
            Today
          </button>
        )}
        <div className="relative ml-auto w-full sm:w-64">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-ink-muted" />
          <Input className="pl-9" placeholder="Search name or number" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
      </div>

      {data?.settings && (
        <p className="text-xs text-ink-muted">
          Email reminders: <span className="font-medium text-ink">{data.settings.email_mode}</span> (up to{' '}
          {data.settings.daily_email_limit} a day) · Notifications: <span className="font-medium text-ink">{data.settings.push_mode}</span>
        </p>
      )}

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        <StatCard
          label="Emails sent"
          icon={<Mail />}
          value={isLoading ? '…' : stats.sent(stats.email)}
          context={`${stats.opened(stats.email)} opened · ${stats.clicked(stats.email)} clicked`}
        />
        <StatCard
          label="Notifications sent"
          icon={<BellRing />}
          value={isLoading ? '…' : stats.sent(stats.push)}
          context={`${stats.opened(stats.push)} shown · ${stats.clicked(stats.push)} tapped`}
        />
        <StatCard
          label="Opened MissionOS"
          icon={<Activity />}
          value={isLoading ? '…' : (data?.app_opens.length ?? 0)}
          context={day === today ? 'today' : formatNyDateShort(`${day}T12:00:00`)}
        />
        <StatCard
          label="Active in the last 7 days"
          icon={<LogIn />}
          value={isLoading ? '…' : stats.recent}
          context={`of ${stats.accounts} member logins · ${stats.never} never signed in`}
          tone={stats.failed > 0 ? 'warning' : 'neutral'}
        />
      </div>

      <Card padding="compact" className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-ink">
            Reminders {day === today ? 'today' : `on ${formatNyDateShort(`${day}T12:00:00`)}`} ({deliveries.length})
          </h2>
          <div className="flex gap-2">
            <Select value={channel} onChange={(e) => setChannel(e.target.value as typeof channel)} aria-label="Channel">
              <option value="all">Email + notifications</option>
              <option value="email">Email</option>
              <option value="push">Notifications</option>
            </Select>
            <Select value={show} onChange={(e) => setShow(e.target.value as typeof show)} aria-label="Show">
              <option value="all">All</option>
              <option value="opened">Opened / shown</option>
              <option value="not_opened">Not opened</option>
              <option value="failed">Failed</option>
            </Select>
          </div>
        </div>
        {deliveries.length === 0 ? (
          <EmptyState icon={<Mail />} title="No reminders" message="Nothing was sent on this day (reminders go out 3 days and 1 day before an item)." />
        ) : (
          <ul className="divide-y divide-line">
            {deliveries.map((d) => (
              <li key={d.delivery_id} className="flex flex-wrap items-start justify-between gap-2 py-2 text-sm">
                <div className="min-w-0">
                  <p className="font-medium text-ink">
                    {d.display_name} {d.member_number && <span className="text-xs text-ink-muted">{d.member_number}</span>}
                  </p>
                  <p className="text-xs text-ink-secondary">
                    {d.channel === 'push' ? <Smartphone className="mr-1 inline h-3.5 w-3.5" /> : <Mail className="mr-1 inline h-3.5 w-3.5" />}
                    {d.reminder_type === 'nudge' ? 'Will you attend?' : 'Reminder'} · {d.item_title ?? 'Item'}
                    {d.group_name ? ` — ${d.group_name}` : ''} · {d.days_before === 1 ? '1 day before' : '3 days before'}
                  </p>
                  <p className="text-xs text-ink-muted">
                    Sent {when(d.sent_at)}
                    {d.opened_at ? ` · ${d.channel === 'push' ? 'shown' : 'opened'} ${when(d.opened_at)}` : ''}
                    {d.clicked_at ? ` · ${d.channel === 'push' ? 'tapped' : 'clicked'} ${when(d.clicked_at)}` : ''}
                  </p>
                  {d.error && <p className="text-xs text-danger-700">{d.error}</p>}
                </div>
                <DeliveryStatus d={d} />
              </li>
            ))}
          </ul>
        )}
        <p className="text-xs text-ink-muted">
          Email &ldquo;opened&rdquo; is approximate: some mail apps load pictures automatically (counted as opened), others
          block them (not counted even when read). &ldquo;Clicked&rdquo; means the Open My Events button was tapped.
        </p>
      </Card>

      <Card padding="compact" className="space-y-2">
        <h2 className="text-sm font-semibold text-ink">
          Opened MissionOS {day === today ? 'today' : `on ${formatNyDateShort(`${day}T12:00:00`)}`} ({data?.app_opens.length ?? 0})
        </h2>
        {(data?.app_opens.length ?? 0) === 0 ? (
          <p className="text-sm text-ink-muted">No one yet.</p>
        ) : (
          <ul className="divide-y divide-line">
            {data!.app_opens.map((a) => (
              <li key={a.profile_id} className="flex items-center justify-between gap-2 py-1.5 text-sm">
                <span className="text-ink">
                  {a.display_name} {a.member_number && <span className="text-xs text-ink-muted">{a.member_number}</span>}
                </span>
                <span className="text-xs text-ink-secondary">
                  {formatNyTime(a.first_at)}
                  {a.opens > 1 ? ` – ${formatNyTime(a.last_at)} · ${a.opens}×` : ''}
                </span>
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card padding="compact" className="space-y-2">
        <h2 className="text-sm font-semibold text-ink">
          Member logins ({accountRows.length}) · {stats.devices} with notifications on
        </h2>
        <ul className="divide-y divide-line">
          {accountRows.map((a) => (
            <li key={a.member_id} className="flex flex-wrap items-center justify-between gap-2 py-1.5 text-sm">
              <span className="text-ink">
                {a.display_name} {a.member_number && <span className="text-xs text-ink-muted">{a.member_number}</span>}
                {a.push_devices > 0 && <BellRing className="ml-1 inline h-3.5 w-3.5 text-primary" aria-label="Notifications on" />}
              </span>
              <span className="text-xs text-ink-secondary">
                Signed in: {ago(a.last_sign_in_at, today)} · In the app: {ago(a.last_active_at, today)}
              </span>
            </li>
          ))}
        </ul>
        <p className="text-xs text-ink-muted">
          Members without a login are not listed here (see People → Directory → Member logins).
        </p>
      </Card>
    </div>
  );
}
