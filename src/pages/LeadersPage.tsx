// Pastoral -> Leaders: Area, Chapter and Unit Servant Leaders in one place (Pass 9.20, Ron 2026-10-19).
// Appoint (husband and wife linked in the same step), end an appointment, and grant / revoke app access.
// Household leaders stay on each household's page.
// Pass 9.20A (Ron, 2026-10-20): shows coordinators (FMC New York Coordinators) and marks MFC New York / FMC New York
// as sub-areas overseen by New York Area (no Appoint there).
import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useCurrentOrganization } from '../hooks/use-current-organization';
import { normalizeError } from '../lib/supabase/errors';
import { LEVEL_LABELS, invalidateLeaderOffices, useLeaderOffices, type LeaderOffice, type OfficeNodeType } from '../features/leaders/api';
import { AppointLeaderModal } from '../features/leaders/AppointLeaderModal';
import { ConcludeServantLeaderModal } from '../features/households/components/ConcludeServantLeaderModal';
import { ServantLeaderAccessModal } from '../features/households/components/ServantLeaderAccessModal';
import { Alert, Badge, Button, Card } from '../components/ui';

const GROUPS: { type: OfficeNodeType; title: string }[] = [
  { type: 'area_state', title: 'Area' },
  { type: 'chapter', title: 'Chapters' },
  { type: 'unit', title: 'Units' },
];

type Dialog = { kind: 'appoint' | 'conclude' | 'access'; office: LeaderOffice } | null;

function leaderNames(o: LeaderOffice) {
  const l = o.leader!;
  return l.spouse ? `${l.display_name} & ${l.spouse.display_name}` : l.display_name;
}

export default function LeadersPage() {
  const qc = useQueryClient();
  const { organization } = useCurrentOrganization();
  const orgId = organization?.id ?? null;
  const { data, isLoading, error, refetch } = useLeaderOffices(orgId);
  const [dialog, setDialog] = useState<Dialog>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const done = async (msg: string) => {
    setNotice(msg);
    await invalidateLeaderOffices(qc);
    await refetch();
  };

  if (isLoading) return <div className="p-8 text-center text-sm text-ink-muted">Loading leaders…</div>;
  if (error || !data || !orgId) {
    return (
      <Alert variant="warning" title="Leaders">
        {error ? normalizeError(error).message : 'Please select an active organization.'}
      </Alert>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-5">
      <div>
        <h1 className="text-xl font-bold text-ink">Leaders</h1>
        <p className="text-sm text-ink-secondary">
          Area, Chapter and Unit Servant Leaders. Couples are appointed together; app access is given once a leader has a login.
        </p>
      </div>

      {notice && (
        <Alert variant="success" title="Done">
          {notice}
        </Alert>
      )}

      {GROUPS.map((g) => {
        const offices = data.offices.filter((o) => o.node_type === g.type);
        if (offices.length === 0) return null;
        return (
          <section key={g.type} className="space-y-2">
            <h2 className="text-small font-semibold uppercase tracking-wide text-ink-secondary">{g.title}</h2>
            <Card padding="none">
              <ul className="divide-y divide-line">
                {offices.map((o) => {
                  const l = o.leader;
                  return (
                    <li key={o.node_id} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-ink">{o.node_name}</p>
                        {o.parent_name && g.type !== 'area_state' && (
                          <p className="text-xs text-ink-muted">{o.parent_name}</p>
                        )}
                        {l ? (
                          <>
                            <p className="mt-1 text-sm text-ink">{leaderNames(o)}</p>
                            <p className="text-xs text-ink-muted">
                              {[l.member_number, l.spouse?.member_number].filter(Boolean).join(' · ')}
                              {l.effective_from ? ` · since ${l.effective_from}` : ''}
                            </p>
                          </>
                        ) : o.coordinator ? (
                          <>
                            <p className="mt-1 text-sm text-ink">
                              {o.coordinator.partner
                                ? `${o.coordinator.display_name} & ${o.coordinator.partner.display_name}`
                                : o.coordinator.display_name}
                            </p>
                            <p className="text-xs text-ink-muted">
                              {o.coordinator.role_name}
                              {[o.coordinator.member_number, o.coordinator.partner?.member_number].filter(Boolean).length > 0
                                ? ` · ${[o.coordinator.member_number, o.coordinator.partner?.member_number].filter(Boolean).join(' · ')}`
                                : ''}
                            </p>
                          </>
                        ) : o.is_sub_area ? (
                          <p className="mt-1 text-sm text-ink-muted">Overseen by {o.parent_name ?? 'the Area'}</p>
                        ) : (
                          <p className="mt-1 text-sm italic text-ink-muted">Vacant</p>
                        )}
                      </div>
                      <div className="flex flex-wrap items-center gap-2">
                        {l &&
                          (l.access_status === 'active' ? (
                            <Badge variant="success">App access</Badge>
                          ) : l.has_login ? (
                            <Badge variant="warning">No app access yet</Badge>
                          ) : (
                            <Badge variant="neutral">No login yet</Badge>
                          ))}
                        {!l && !o.coordinator && !o.is_sub_area && data.can_appoint && (
                          <Button size="sm" onClick={() => setDialog({ kind: 'appoint', office: o })}>
                            Appoint
                          </Button>
                        )}
                        {l && data.can_manage_access && (l.has_login || l.access_status === 'active') && (
                          <Button size="sm" variant="outline" onClick={() => setDialog({ kind: 'access', office: o })}>
                            App access
                          </Button>
                        )}
                        {l && data.can_conclude && (
                          <Button size="sm" variant="ghost" onClick={() => setDialog({ kind: 'conclude', office: o })}>
                            End appointment
                          </Button>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ul>
            </Card>
          </section>
        );
      })}

      <p className="text-xs text-ink-muted">
        App access goes with the appointment of the leader on record (the husband, for a couple). To change a leader, end
        the appointment, then appoint the new leader.
      </p>

      {dialog?.kind === 'appoint' && (
        <AppointLeaderModal orgId={orgId} office={dialog.office} onClose={() => setDialog(null)} onDone={done} />
      )}
      {dialog?.kind === 'conclude' && dialog.office.leader && (
        <ConcludeServantLeaderModal
          isOpen
          onClose={() => setDialog(null)}
          organizationId={orgId}
          governanceNodeId={dialog.office.node_id}
          governanceNodeName={dialog.office.node_name}
          leadershipAssignmentId={dialog.office.leader.assignment_id}
          leaderDisplayName={leaderNames(dialog.office)}
          roleName={dialog.office.leader.role_name || `${LEVEL_LABELS[dialog.office.node_type]} Servant Leader`}
          onSuccessToast={done}
        />
      )}
      {dialog?.kind === 'access' && dialog.office.leader && (
        <ServantLeaderAccessModal
          isOpen
          onClose={() => {
            setDialog(null);
            void invalidateLeaderOffices(qc);
          }}
          organizationId={orgId}
          leadershipAssignmentId={dialog.office.leader.assignment_id}
          leaderDisplayName={dialog.office.leader.display_name}
          roleName={dialog.office.leader.role_name || `${LEVEL_LABELS[dialog.office.node_type]} Servant Leader`}
          governanceNodeName={dialog.office.node_name}
          onSuccessToast={done}
        />
      )}
    </div>
  );
}
