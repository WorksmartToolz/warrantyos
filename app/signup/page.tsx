import { validateInvitationToken } from '@/lib/core/invitations'
import { SignupForm } from './signup-form'

interface SignupPageProps {
  searchParams: { token?: string }
}

export default async function SignupPage({ searchParams }: SignupPageProps) {
  const token = searchParams.token

  if (!token) {
    return <ErrorPage message="No invitation token in this link. Ask your platform admin for a new invitation." />
  }

  const invitation = await validateInvitationToken(token)

  if (!invitation) {
    return (
      <ErrorPage message="This invitation link is invalid, has expired, or has already been used. Ask your platform admin for a new invitation." />
    )
  }

  return (
    <main className="flex min-h-screen items-center justify-center bg-neutral-50">
      <div className="w-full max-w-sm rounded-lg border border-neutral-200 bg-white p-8 shadow-sm">
        <h1 className="mb-1 text-xl font-semibold tracking-tight">WarrantyOS</h1>
        <p className="mb-6 text-sm text-neutral-500">
          Complete your account setup
        </p>

        <SignupForm
          token={token}
          email={invitation.email}
          defaultFullName={invitation.full_name}
        />
      </div>
    </main>
  )
}

function ErrorPage({ message }: { message: string }) {
  return (
    <main className="flex min-h-screen items-center justify-center bg-neutral-50">
      <div className="w-full max-w-sm rounded-lg border border-neutral-200 bg-white p-8 shadow-sm">
        <h1 className="mb-1 text-xl font-semibold tracking-tight">WarrantyOS</h1>
        <p className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {message}
        </p>
      </div>
    </main>
  )
}
