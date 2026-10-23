// Structure (Pass 9.38C, Ron 2026-10-22): the tree above households — Area, sub-areas, sections, chapters, units.
// Administrators add a chapter under a section and a unit under a chapter, rename, and retire what is empty.
import { useMemo, useState } from 'react';
import { ChevronDown, ChevronRight, Network, Pencil, Plus, Trash2 } from 'lucide-react';
import { useOrganizationContext } from '../hooks/use-organization-context';
import { normalizeError } from '../lib/supabase/errors';
import {
  useAddStandardSections,
  useCreateStructureNode,
  useRenameStructureNode,
  useRetireStructureNode,
  useStructureTree,
  type StructureNode,
} from '../features/structure/api';
import { Alert, Badge, Button, Card, EmptyState, Input, Modal, PageHeader, Skeleton } from '../components/ui';

const TYPE_LABEL: Record<string, string> = {
  area_state: 'Area',
  section: 'Section',
  chapter: 'Chapter',
  unit: 'Unit',
};
const KIND_LABEL: Record<string, string> = {
  couples: 'Couples', handmaids: 'Handmaids', servants: 'Servants', singles: 'Singles', campus: 'Campus',
  youth: 'Youth', kids: 'Kids',
};

type Dialog =
  | { kind: 'add'; parent: StructureNode; type: 'chapter' | 'unit' }
  | { kind: 'rename'; node: StructureNode }
  | { kind: 'retire'; node: StructureNode }
  | null;

function counts(n: StructureNode): string {
  const parts: string[] = [];
  if (n.child_nodes > 0) {
    const what = n.type === 'chapter' ? 'unit' : n.type === 'section' ? 'chapter' : 'part';
    parts.push(`${n.child_nodes} ${what}${n.child_nodes === 1 ? '' : 's'}`);
  }
  if (n.households > 0) parts.push(`${n.households} household${n.households === 1 ? '' : 's'}`);
  if (n.leaders > 0) parts.push(`${n.leaders} leader appointment${n.leaders === 1 ? '' : 's'}`);
  return parts.join(' · ');
}

export default function StructurePage() {
  const { activeOrganization } = useOrganizationContext();
  const orgId = activeOrganization?.id ?? null;
  const { data, isLoading, error } = useStructureTree(orgId);
  const create = useCreateStructureNode(orgId);
  const rename = useRenameStructureNode(orgId);
  const retire = useRetireStructureNode(orgId);
  const addSections = useAddStandardSections(orgId);

  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [dialog, setDialog] = useState<Dialog>(null);
  const [text, setText] = useState('');
  const [dialogError, setDialogError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);

  const { roots, children } = useMemo(() => {
    const nodes = data?.nodes ?? [];
    const ids = new Set(nodes.map((n) => n.id));
    const kids = new Map<string, StructureNode[]>();
    const top: StructureNode[] = [];
    for (const n of nodes) {
      if (n.parent_id && ids.has(n.parent_id)) {
        if (!kids.has(n.parent_id)) kids.set(n.parent_id, []);
        kids.get(n.parent_id)!.push(n);
      } else {
        top.push(n);
      }
    }
    return { roots: top, children: kids };
  }, [data]);

  const open = (d: Dialog) => {
    setDialog(d);
    setDialogError(null);
    setText(d && d.kind === 'rename' ? d.node.name : '');
  };

  const submit = async () => {
    if (!dialog) return;
    setDialogError(null);
    try {
      if (dialog.kind === 'add') {
        await create.mutateAsync({ parentId: dialog.parent.id, type: dialog.type, name: text });
        setNotice(`${TYPE_LABEL[dialog.type]} “${text.trim()}” added under ${dialog.parent.name}.`);
      } else if (dialog.kind === 'rename') {
        await rename.mutateAsync({ nodeId: dialog.node.id, name: text });
        setNotice(`Renamed to “${text.trim()}”.`);
      } else {
        await retire.mutateAsync({ nodeId: dialog.node.id, reason: text || undefined });
        setNotice(`${dialog.node.name} was retired.`);
      }
      setDialog(null);
    } catch (e) {
      setDialogError(normalizeError(e).message);
    }
  };

  const toggle = (id: string) =>
    setCollapsed((s) => {
      const next = new Set(s);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const renderNode = (n: StructureNode, depth: number) => {
    const kids = children.get(n.id) ?? [];
    const isCollapsed = collapsed.has(n.id);
    const missing = (data?.missing_sections?.[n.id] ?? []).filter(Boolean);
    const editable = n.type === 'section' || n.type === 'chapter' || n.type === 'unit';
    const empty = n.child_nodes === 0 && n.households === 0 && n.leaders === 0;
    return (
      <li key={n.id}>
        <div
          className="flex flex-wrap items-center gap-x-2 gap-y-1 border-b border-line py-2"
          style={{ paddingLeft: `${depth * 16}px` }}
        >
          {kids.length > 0 ? (
            <button
              type="button"
              aria-label={isCollapsed ? `Show what is under ${n.name}` : `Hide what is under ${n.name}`}
              className="rounded p-0.5 text-ink-muted hover:bg-surface-muted"
              onClick={() => toggle(n.id)}
            >
              {isCollapsed ? <ChevronRight className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
            </button>
          ) : (
            <span className="inline-block w-5" />
          )}
          <Badge variant={n.type === 'section' ? 'info' : 'neutral'}>{TYPE_LABEL[n.type] ?? n.type}</Badge>
          <span className="min-w-0 font-medium text-ink">{n.name}</span>
          <span className="text-xs text-ink-muted">{counts(n)}</span>
          <span className="ml-auto flex flex-wrap gap-1">
            {n.type === 'section' && (
              <Button size="sm" variant="ghost" icon={<Plus className="h-4 w-4" />} onClick={() => open({ kind: 'add', parent: n, type: 'chapter' })}>
                Chapter
              </Button>
            )}
            {n.type === 'chapter' && (
              <Button size="sm" variant="ghost" icon={<Plus className="h-4 w-4" />} onClick={() => open({ kind: 'add', parent: n, type: 'unit' })}>
                Unit
              </Button>
            )}
            {editable && (
              <Button size="sm" variant="ghost" aria-label={`Rename ${n.name}`} icon={<Pencil className="h-4 w-4" />} onClick={() => open({ kind: 'rename', node: n })} />
            )}
            {editable && empty && (
              <Button size="sm" variant="ghost" aria-label={`Retire ${n.name}`} icon={<Trash2 className="h-4 w-4" />} onClick={() => open({ kind: 'retire', node: n })} />
            )}
          </span>
          {n.type === 'area_state' && missing.length > 0 && (
            <div className="w-full pl-7 text-xs text-ink-secondary">
              Missing sections: {missing.map((k) => KIND_LABEL[k] ?? k).join(', ')}{' '}
              <Button
                size="sm"
                variant="outline"
                loading={addSections.isPending}
                onClick={() =>
                  addSections.mutate(n.id, {
                    onSuccess: () => setNotice(`Sections added to ${n.name}.`),
                    onError: (e) => setNotice(normalizeError(e).message),
                  })
                }
              >
                Add them
              </Button>
            </div>
          )}
        </div>
        {kids.length > 0 && !isCollapsed && <ul>{kids.map((k) => renderNode(k, depth + 1))}</ul>}
      </li>
    );
  };

  if (error) {
    const e = normalizeError(error);
    return (
      <Alert variant="warning" title="Structure">
        {e.code === '42501' ? 'Only administrators can manage the structure.' : e.message}
      </Alert>
    );
  }

  const dialogTitle =
    dialog?.kind === 'add'
      ? `Add a ${dialog.type} under ${dialog.parent.name}`
      : dialog?.kind === 'rename'
        ? `Rename ${dialog.node.name}`
        : dialog?.kind === 'retire'
          ? `Retire ${dialog.node.name}?`
          : '';

  return (
    <div className="space-y-6">
      <PageHeader
        title="Structure"
        description="Areas, sections, chapters and units. Add a chapter under its section and a unit under its chapter; households are created on the Households page."
      />
      {notice && (
        <Alert variant="info" title="Done">
          {notice}
        </Alert>
      )}
      {isLoading ? (
        <div className="space-y-2">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
        </div>
      ) : roots.length === 0 ? (
        <EmptyState icon={<Network />} title="No structure yet" message="Nothing to show." />
      ) : (
        <Card padding="compact">
          <ul className="text-sm">{roots.map((r) => renderNode(r, 0))}</ul>
        </Card>
      )}
      <p className="text-xs text-ink-muted">
        A chapter or unit can be retired only when nothing is under it and it has no servant leaders. Retired ones
        stay in the history.
      </p>

      <Modal
        open={dialog !== null}
        onClose={() => setDialog(null)}
        title={dialogTitle}
        size="sm"
        footer={
          <div className="flex justify-end gap-2">
            <Button variant="ghost" onClick={() => setDialog(null)}>
              Cancel
            </Button>
            <Button
              variant={dialog?.kind === 'retire' ? 'danger' : 'primary'}
              loading={create.isPending || rename.isPending || retire.isPending}
              disabled={dialog?.kind !== 'retire' && text.trim().length < 2}
              onClick={submit}
            >
              {dialog?.kind === 'add' ? 'Add' : dialog?.kind === 'rename' ? 'Save' : 'Retire'}
            </Button>
          </div>
        }
      >
        <div className="space-y-2">
          {dialog?.kind === 'retire' ? (
            <>
              <p className="text-sm text-ink-secondary">It will no longer show anywhere in the app.</p>
              <Input placeholder="Reason (optional)" value={text} onChange={(e) => setText(e.target.value)} aria-label="Reason" />
            </>
          ) : (
            <Input
              autoFocus
              placeholder={dialog?.kind === 'add' ? (dialog.type === 'chapter' ? 'e.g. Singles Chapter' : 'e.g. Queens Unit') : ''}
              value={text}
              onChange={(e) => setText(e.target.value)}
              aria-label="Name"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && text.trim().length >= 2) void submit();
              }}
            />
          )}
          {dialogError && <p className="text-xs text-danger-700">{dialogError}</p>}
        </div>
      </Modal>
    </div>
  );
}
