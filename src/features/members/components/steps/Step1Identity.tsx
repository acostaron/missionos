import type { UseFormRegister, FieldErrors } from 'react-hook-form';
import type { CreateMemberFormData } from '../schema';

interface StepProps {
  register: UseFormRegister<CreateMemberFormData>;
  errors: FieldErrors<CreateMemberFormData>;
}

export function Step1Identity({ register, errors }: StepProps) {
  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-lg font-semibold text-slate-100">Member Identity</h2>
        <p className="text-sm text-slate-400">
          Enter the personal identity details of the new member. Required fields are marked with an asterisk (*).
        </p>
      </div>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {/* Given Names */}
        <div>
          <label htmlFor="givenNames" className="block text-xs font-medium text-slate-300">
            Given Name(s) <span className="text-rose-400">*</span>
          </label>
          <input
            id="givenNames"
            type="text"
            {...register('givenNames')}
            placeholder="e.g. Maria Clara"
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
          {errors.givenNames && (
            <p className="mt-1 text-xs text-rose-400">{errors.givenNames.message}</p>
          )}
        </div>

        {/* Family Name */}
        <div>
          <label htmlFor="familyName" className="block text-xs font-medium text-slate-300">
            Family Name <span className="text-rose-400">*</span>
          </label>
          <input
            id="familyName"
            type="text"
            {...register('familyName')}
            placeholder="e.g. Santos"
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
          {errors.familyName && (
            <p className="mt-1 text-xs text-rose-400">{errors.familyName.message}</p>
          )}
        </div>

        {/* Middle Names */}
        <div>
          <label htmlFor="middleNames" className="block text-xs font-medium text-slate-300">
            Middle Name(s) <span className="text-slate-500">(optional)</span>
          </label>
          <input
            id="middleNames"
            type="text"
            {...register('middleNames')}
            placeholder="e.g. Cruz"
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
        </div>

        {/* Preferred Name */}
        <div>
          <label htmlFor="preferredName" className="block text-xs font-medium text-slate-300">
            Preferred First Name <span className="text-slate-500">(optional)</span>
          </label>
          <input
            id="preferredName"
            type="text"
            {...register('preferredName')}
            placeholder="e.g. Clara"
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
        </div>

        {/* Birth Date */}
        <div>
          <label htmlFor="birthDate" className="block text-xs font-medium text-slate-300">
            Birth Date <span className="text-slate-500">(optional)</span>
          </label>
          <input
            id="birthDate"
            type="date"
            {...register('birthDate')}
            max={new Date().toISOString().split('T')[0]}
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          />
          {errors.birthDate && (
            <p className="mt-1 text-xs text-rose-400">{errors.birthDate.message}</p>
          )}
        </div>

        {/* Sex */}
        <div>
          <label htmlFor="sex" className="block text-xs font-medium text-slate-300">
            Sex <span className="text-slate-500">(optional)</span>
          </label>
          <select
            id="sex"
            {...register('sex')}
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="">Select sex…</option>
            <option value="female">Female</option>
            <option value="male">Male</option>
            <option value="other">Other</option>
          </select>
        </div>

        {/* Civil Status */}
        <div>
          <label htmlFor="civilStatus" className="block text-xs font-medium text-slate-300">
            Civil Status <span className="text-slate-500">(optional)</span>
          </label>
          <select
            id="civilStatus"
            {...register('civilStatus')}
            className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
          >
            <option value="">Select civil status…</option>
            <option value="single">Single</option>
            <option value="married">Married</option>
            <option value="widowed">Widowed</option>
            <option value="separated">Separated</option>
            <option value="divorced">Divorced</option>
          </select>
        </div>
      </div>
    </div>
  );
}
