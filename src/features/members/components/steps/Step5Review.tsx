import type { CreateMemberFormData } from '../schema';
import type { PlacementNodeItem } from '../../types';

interface StepProps {
  formData: CreateMemberFormData;
  placementNodes?: PlacementNodeItem[];
  canManageIdentifiers: boolean;
  canManagePlacements: boolean;
  canManageContacts: boolean;
  canManageAddresses: boolean;
}

export function Step5Review({
  formData,
  placementNodes,
  canManageIdentifiers,
  canManagePlacements,
  canManageContacts,
  canManageAddresses,
}: StepProps) {
  // Find selected placement node if any
  const selectedPlacement = placementNodes?.find(
    (n) => n.governance_node_id === formData.governanceNodeId
  );

  const hasContact =
    canManageContacts && (formData.email?.trim() || formData.phone?.trim());
  const hasAddress =
    canManageAddresses && (formData.addressLine1?.trim() || formData.cityName?.trim());

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-slate-100">Review Member Information</h2>
        <p className="text-sm text-slate-400">
          Please confirm the member details below before creating the record.
        </p>
      </div>

      <div className="space-y-4">
        {/* Section: Identity */}
        <div className="rounded-xl border border-slate-700 bg-slate-800/40 p-4">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
            Identity
          </h3>
          <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2 text-sm">
            <div>
              <dt className="text-xs text-slate-500">Full Name</dt>
              <dd className="font-medium text-slate-100">
                {formData.givenNames} {formData.middleNames ? `${formData.middleNames} ` : ''}
                {formData.familyName}
              </dd>
            </div>
            {formData.preferredName && (
              <div>
                <dt className="text-xs text-slate-500">Preferred Name</dt>
                <dd className="text-slate-200">{formData.preferredName}</dd>
              </div>
            )}
            {formData.birthDate && (
              <div>
                <dt className="text-xs text-slate-500">Birth Date</dt>
                <dd className="text-slate-200">{formData.birthDate}</dd>
              </div>
            )}
            {formData.sex && (
              <div>
                <dt className="text-xs text-slate-500">Sex</dt>
                <dd className="text-slate-200 capitalize">{formData.sex}</dd>
              </div>
            )}
            {formData.civilStatus && (
              <div>
                <dt className="text-xs text-slate-500">Civil Status</dt>
                <dd className="text-slate-200 capitalize">{formData.civilStatus}</dd>
              </div>
            )}
          </dl>
        </div>

        {/* Section: Membership & Number */}
        <div className="rounded-xl border border-slate-700 bg-slate-800/40 p-4">
          <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
            Membership
          </h3>
          <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2 text-sm">
            <div>
              <dt className="text-xs text-slate-500">Joined On</dt>
              <dd className="text-slate-200">{formData.joinedOn}</dd>
            </div>
            <div>
              <dt className="text-xs text-slate-500">Home Country</dt>
              <dd className="text-slate-200">{formData.homeCountryCode}</dd>
            </div>
            <div className="sm:col-span-2">
              <dt className="text-xs text-slate-500">Member Number Allocation</dt>
              <dd className="text-slate-200">
                {canManageIdentifiers && formData.allocateMemberNumber ? (
                  <span className="inline-flex items-center gap-1.5 text-emerald-400 font-medium text-xs">
                    <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
                    Next available number will be automatically allocated
                  </span>
                ) : (
                  <span className="text-slate-400 text-xs italic">
                    No member number will be assigned at onboarding
                  </span>
                )}
              </dd>
            </div>
          </dl>
        </div>

        {/* Section: Placement */}
        {canManagePlacements && (
          <div className="rounded-xl border border-slate-700 bg-slate-800/40 p-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
              Governance Placement
            </h3>
            <div className="text-sm">
              {selectedPlacement ? (
                <div>
                  <p className="font-medium text-slate-100">
                    {selectedPlacement.node_name}{' '}
                    <span className="text-xs text-slate-400">({selectedPlacement.node_code})</span>
                  </p>
                  <p className="text-xs text-slate-400 capitalize">
                    {selectedPlacement.node_type_code}
                    {selectedPlacement.parent_node_name && ` · under ${selectedPlacement.parent_node_name}`}
                  </p>
                </div>
              ) : (
                <p className="text-xs text-slate-400 italic">Unplaced for now</p>
              )}
            </div>
          </div>
        )}

        {/* Section: Contact */}
        {hasContact && (
          <div className="rounded-xl border border-slate-700 bg-slate-800/40 p-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
              Contact Points
            </h3>
            <dl className="grid grid-cols-1 gap-2 sm:grid-cols-2 text-sm">
              {formData.email?.trim() && (
                <div>
                  <dt className="text-xs text-slate-500">Email</dt>
                  <dd className="text-slate-200">{formData.email.trim()}</dd>
                </div>
              )}
              {formData.phone?.trim() && (
                <div>
                  <dt className="text-xs text-slate-500">Phone</dt>
                  <dd className="text-slate-200">
                    {formData.phoneCountryCode ? `+${formData.phoneCountryCode} ` : ''}
                    {formData.phone.trim()}
                  </dd>
                </div>
              )}
            </dl>
          </div>
        )}

        {/* Section: Residential Address */}
        {hasAddress && (
          <div className="rounded-xl border border-slate-700 bg-slate-800/40 p-4">
            <h3 className="text-xs font-semibold uppercase tracking-wider text-slate-400 mb-3">
              Residential Address
            </h3>
            <div className="text-sm text-slate-200">
              <p>{formData.addressLine1}</p>
              {formData.addressLine2?.trim() && <p>{formData.addressLine2.trim()}</p>}
              <p>
                {[formData.cityName, formData.stateProvinceName, formData.postalCode]
                  .filter(Boolean)
                  .join(', ')}
              </p>
              <p className="text-xs text-slate-400 mt-1">{formData.addressCountryCode}</p>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
