'use client'

import { useFormState, useFormStatus } from 'react-dom'
import { completeSignup, type SignupState } from '@/lib/actions/signup'

function SubmitButton() {
  const { pending } = useFormStatus()
  return (
    <button
      type="submit"
      disabled={pending}
      className="w-full rounded-md bg-neutral-900 px-4 py-2 text-sm font-medium text-white hover:bg-neutral-700 disabled:opacity-50"
    >
      {pending ? 'Creating account…' : 'Create account'}
    </button>
  )
}

const initialState: SignupState = { error: null }

interface SignupFormProps {
  token: string
  email: string
  defaultFullName: string | null
}

export function SignupForm({ token, email, defaultFullName }: SignupFormProps) {
  const [state, formAction] = useFormState(completeSignup, initialState)

  return (
    <form action={formAction} className="space-y-4">
      {/* Token passed as hidden field — re-validated server-side on submit */}
      <input type="hidden" name="token" value={token} />

      <div>
        <label className="mb-1 block text-sm font-medium text-neutral-700">
          Email
        </label>
        <input
          type="email"
          value={email}
          disabled
          className="w-full rounded-md border border-neutral-200 bg-neutral-50 px-3 py-2 text-sm text-neutral-500"
        />
      </div>

      <div>
        <label
          htmlFor="full_name"
          className="mb-1 block text-sm font-medium text-neutral-700"
        >
          Full name
        </label>
        <input
          id="full_name"
          name="full_name"
          type="text"
          defaultValue={defaultFullName ?? ''}
          autoComplete="name"
          required
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-500 focus:outline-none focus:ring-1 focus:ring-neutral-500"
        />
      </div>

      <div>
        <label
          htmlFor="password"
          className="mb-1 block text-sm font-medium text-neutral-700"
        >
          Password
        </label>
        <input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          required
          minLength={8}
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm focus:border-neutral-500 focus:outline-none focus:ring-1 focus:ring-neutral-500"
        />
        <p className="mt-1 text-xs text-neutral-500">Minimum 8 characters</p>
      </div>

      {state.error && (
        <p className="rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {state.error}
        </p>
      )}

      <SubmitButton />
    </form>
  )
}
