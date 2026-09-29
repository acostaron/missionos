import type { UseFormRegister, FieldErrors } from 'react-hook-form';
import type { CreateMemberFormData } from '../schema';

interface StepProps {
  register: UseFormRegister<CreateMemberFormData>;
  errors: FieldErrors<CreateMemberFormData>;
  canManageIdentifiers: boolean;
}

export function Step2Membership({ register, errors, canManageIdentifiers }: StepProps) {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-slate-100">Membership Details</h2>
        <p className="text-sm text-slate-400">
          Configure joining date, home country, and optional member number allocation.
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {/* Joined Date */}
        <div>
          <label htmlFor="joinedOn" className="block text-xs font-medium text-slate-300">
            Joined On <span className="text-rose-400">*</span>
          </label>
          <input
            id="joinedOn"
            type="date"
            {...register('joinedOn')}
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
          {errors.joinedOn && (
            <p className="mt-1 text-xs text-rose-400">{errors.joinedOn.message}</p>
          )}
        </div>

        {/* Home Country */}
        <div>
          <label htmlFor="homeCountryCode" className="block text-xs font-medium text-slate-300">
            Home Country Code
          </label>
          <select
            id="homeCountryCode"
            {...register('homeCountryCode')}
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="US">United States (US)</option>
            <option value="PH">Philippines (PH)</option>
            <option value="CA">Canada (CA)</option>
            <option value="GB">United Kingdom (GB)</option>
            <option value="AU">Australia (AU)</option>
          </select>
        </div>
      </div>

      {/* Member Number Allocation Toggle */}
      {canManageIdentifiers ? (
        <div className="rounded-xl border border-slate-700/80 bg-slate-800/60 p-4">
          <div className="flex items-start gap-3">
            <div className="flex h-5 items-center">
              <input
                id="allocateMemberNumber"
                type="checkbox"
                {...register('allocateMemberNumber')}
                className="h-4 w-4 rounded border-slate-700 bg-slate-900 text-indigo-600 focus:ring-indigo-500 focus:ring-offset-slate-900"
              />
            </div>
            <div className="text-sm">
              <label htmlFor="allocateMemberNumber" className="font-medium text-slate-200 cursor-pointer">
                Assign member number
              </label>
              <p className="text-xs text-slate-400 mt-0.5">
                When enabled, MissionOS will assign the next available member number when the member is created.
              </p>
            </div>
          </div>
        </div>
      ) : (
        <div className="rounded-lg border border-slate-800 bg-slate-900/40 p-3 text-xs text-slate-500 italic">
          Member number allocation is restricted for your role. Member will be created without an assigned number.
        </div>
      )}
    </div>
  );
}
