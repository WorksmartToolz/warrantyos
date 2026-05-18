'use client'

import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { cn } from '@/lib/utils'

interface NavLinkProps {
  href: string
  matchPrefix?: string
  exact?: boolean
  children: React.ReactNode
}

export function NavLink({ href, matchPrefix, exact, children }: NavLinkProps) {
  const pathname = usePathname()
  const prefix = matchPrefix ?? href
  const isActive = exact
    ? pathname === href
    : pathname === prefix || pathname.startsWith(prefix + '/')

  return (
    <Link
      href={href}
      className={cn(
        'flex items-center rounded-md px-3 py-2 text-sm font-medium transition-colors',
        isActive
          ? 'bg-neutral-100 text-neutral-900'
          : 'text-neutral-500 hover:bg-neutral-50 hover:text-neutral-900'
      )}
    >
      {children}
    </Link>
  )
}
