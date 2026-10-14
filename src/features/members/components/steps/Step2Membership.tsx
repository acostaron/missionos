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

      {/* Member Number (from Finance) */}
      {canManageIdentifiers ? (
        <div className="space-y-1.5">
          <label htmlFor="memberNumber" className="block text-xs font-medium text-slate-300">
            Member number (from Finance)
          </label>
          <input
            id="memberNumber"
            type="text"
            placeholder="e.g. NY10560"
            {...register('memberNumber')}
            className="block w-full max-w-sm rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500 font-mono"
          />
          <p className="text-xs text-slate-400">
            Use the envelope number assigned by the Finance Group. Leave blank if it hasn't been assigned yet.
          </p>
          {errors.memberNumber && (
            <p className="mt-1 text-xs text-rose-400">{errors.memberNumber.message}</p>
          )}
        </div>
      ) : (
        <div className="rounded-lg border border-slate-800 bg-slate-900/40 p-3 text-xs text-slate-500 italic">
          Member numbers are added by an administrator.
        </div>
      )}
    </div>
  );
}
