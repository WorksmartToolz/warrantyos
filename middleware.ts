import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function middleware(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  // Do not add logic between createServerClient and getUser().
  // Session refresh cookies are set inside getUser(); disrupting
  // the flow causes subtle, hard-to-diagnose auth bugs.
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          )
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  const {
    data: { user },
  } = await supabase.auth.getUser()

  const { pathname } = request.nextUrl

  // Platform admin identity is stored in user_metadata at account creation
  // and embedded in the JWT. No DB round-trip needed for routing decisions.
  // A user is either a platform admin or a tenant user — never both.
  const isPlatformAdmin = user?.user_metadata?.is_platform_admin === true

  // ── Public paths ────────────────────────────────────────────
  // Allow unauthenticated access. Redirect authenticated users
  // away so they don't land on auth pages after logging in.
  if (pathname.startsWith('/login') || pathname.startsWith('/signup')) {
    if (user) {
      const dest = isPlatformAdmin ? '/admin' : '/app'
      return NextResponse.redirect(new URL(dest, request.url))
    }
    return supabaseResponse
  }

  // ── Require authentication for all other paths ───────────────
  if (!user) {
    const loginUrl = new URL('/login', request.url)
    loginUrl.searchParams.set('next', pathname)
    return NextResponse.redirect(loginUrl)
  }

  // ── /admin/* — platform admins only ─────────────────────────
  if (pathname.startsWith('/admin')) {
    if (!isPlatformAdmin) {
      return NextResponse.redirect(new URL('/app', request.url))
    }
    return supabaseResponse
  }

  // ── /app/* — tenant users only ───────────────────────────────
  if (pathname.startsWith('/app')) {
    if (isPlatformAdmin) {
      return NextResponse.redirect(new URL('/admin', request.url))
    }

    // Check that the tenant user's account is still active.
    // The "users: authenticated can read their own profile" RLS policy allows
    // this self-read even for suspended/removed users (whose get_user_tenant_id()
    // returns NULL, which would otherwise block the query).
    // TODO: move to JWT claim for production to avoid this per-request DB round-trip.
    const { data: profile } = await supabase
      .from('users')
      .select('status, removed_at')
      .eq('id', user.id)
      .maybeSingle()

    if (!profile || profile.removed_at || profile.status !== 'active') {
      const loginUrl = new URL('/login', request.url)
      loginUrl.searchParams.set('error', 'account_inactive')
      return NextResponse.redirect(loginUrl)
    }

    return supabaseResponse
  }

  // ── Root ─────────────────────────────────────────────────────
  if (pathname === '/') {
    const dest = isPlatformAdmin ? '/admin' : '/app'
    return NextResponse.redirect(new URL(dest, request.url))
  }

  return supabaseResponse
}

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)',
  ],
}
