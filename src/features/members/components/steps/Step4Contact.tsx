import type { UseFormRegister, FieldErrors } from 'react-hook-form';
import type { CreateMemberFormData } from '../schema';

interface StepProps {
  register: UseFormRegister<CreateMemberFormData>;
  errors: FieldErrors<CreateMemberFormData>;
  canManageContacts: boolean;
  canManageAddresses: boolean;
}

export function Step4Contact({
  register,
  errors,
  canManageContacts,
  canManageAddresses,
}: StepProps) {
  return (
    <div className="space-y-8">
      <div>
        <h2 className="text-lg font-semibold text-slate-100">Contact & Address</h2>
        <p className="text-sm text-slate-400">
          Enter optional email, phone, and residential address information.
        </p>
      </div>

      {/* Contact Section */}
      {canManageContacts ? (
        <div className="space-y-4">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Contact Information
          </h3>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <label htmlFor="email" className="block text-xs font-medium text-slate-300">
                Email Address
              </label>
              <input
                id="email"
                type="email"
                {...register('email')}
                placeholder="name@example.com"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
              {errors.email && (
                <p className="mt-1 text-xs text-rose-400">{errors.email.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="phone" className="block text-xs font-medium text-slate-300">
                Phone Number
              </label>
              <div className="mt-1 flex gap-2">
                <select
                  id="phoneCountryCode"
                  {...register('phoneCountryCode')}
                  className="w-24 rounded-lg border border-slate-700 bg-slate-800 px-2 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                >
                  <option value="US">+1 (US)</option>
                  <option value="PH">+63 (PH)</option>
                  <option value="CA">+1 (CA)</option>
                  <option value="GB">+44 (GB)</option>
                  <option value="AU">+61 (AU)</option>
                </select>
                <input
                  id="phone"
                  type="tel"
                  {...register('phone')}
                  placeholder="212-555-0199"
                  className="block w-full flex-1 rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className="rounded-lg border border-slate-800 bg-slate-900/40 p-3 text-xs text-slate-500 italic">
          Contact point management (email/phone) is restricted for your role.
        </div>
      )}

      {/* Address Section */}
      {canManageAddresses ? (
        <div className="space-y-4">
          <h3 className="text-sm font-semibold uppercase tracking-wider text-slate-300">
            Residential Address
          </h3>
          <div className="space-y-4">
            <div>
              <label htmlFor="addressLine1" className="block text-xs font-medium text-slate-300">
                Street Address (Line 1)
              </label>
              <input
                id="addressLine1"
                type="text"
                {...register('addressLine1')}
                placeholder="123 Main St"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
              {errors.addressLine1 && (
                <p className="mt-1 text-xs text-rose-400">{errors.addressLine1.message}</p>
              )}
            </div>

            <div>
              <label htmlFor="addressLine2" className="block text-xs font-medium text-slate-300">
                Apartment, Suite, Unit (Line 2)
              </label>
              <input
                id="addressLine2"
                type="text"
                {...register('addressLine2')}
                placeholder="Apt 4B"
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              />
            </div>

            <div className="grid grid-cols-1 gap-4 sm:grid-cols-3">
              <div>
                <label htmlFor="cityName" className="block text-xs font-medium text-slate-300">
                  City
                </label>
                <input
                  id="cityName"
                  type="text"
                  {...register('cityName')}
                  placeholder="New York"
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
                {errors.cityName && (
                  <p className="mt-1 text-xs text-rose-400">{errors.cityName.message}</p>
                )}
              </div>

              <div>
                <label htmlFor="stateProvinceName" className="block text-xs font-medium text-slate-300">
                  State / Province
                </label>
                <input
                  id="stateProvinceName"
                  type="text"
                  {...register('stateProvinceName')}
                  placeholder="NY"
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>

              <div>
                <label htmlFor="postalCode" className="block text-xs font-medium text-slate-300">
                  Postal Code
                </label>
                <input
                  id="postalCode"
                  type="text"
                  {...register('postalCode')}
                  placeholder="10001"
                  className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 placeholder-slate-500 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
                />
              </div>
            </div>

            <div className="sm:w-1/3">
              <label htmlFor="addressCountryCode" className="block text-xs font-medium text-slate-300">
                Country
              </label>
              <select
                id="addressCountryCode"
                {...register('addressCountryCode')}
                className="mt-1 block w-full rounded-lg border border-slate-700 bg-slate-800 px-3 py-2 text-sm text-slate-100 focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
              >
                <option value="US">United States (US)</option>
                <option value="PH">Philippines (PH)</option>
                <option value="CA">Canada (CA)</option>
                <option value="GB">United Kingdom (GB)</option>
                <option value="AU">Australia (AU)</option>
              </select>
              {errors.addressCountryCode && (
                <p className="mt-1 text-xs text-rose-400">{errors.addressCountryCode.message}</p>
              )}
            </div>
          </div>
        </div>
      ) : (
        <div className="rounded-lg border border-slate-800 bg-slate-900/40 p-3 text-xs text-slate-500 italic">
          Residential address management is restricted for your role.
        </div>
      )}
    </div>
  );
}
