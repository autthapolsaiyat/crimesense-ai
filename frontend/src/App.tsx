import DarkModeToggle from './components/DarkModeToggle'
import { Toaster } from 'sonner'
import CasesPage from './components/CasesPage'

export default function App() {
  return (
    <div className="min-h-screen bg-white text-black dark:bg-neutral-950 dark:text-neutral-100">
      <header className="sticky top-0 z-10 backdrop-blur border-b dark:border-neutral-900 bg-white/70 dark:bg-neutral-950/60">
        <div className="mx-auto max-w-7xl px-4 py-3 flex items-center justify-between">
          <a className="flex items-center gap-2" href="/">
            <img src="/logo.svg" alt="CrimeSenseAI" className="h-6 w-6"/>
            <span className="font-semibold">CrimeSenseAI</span>
          </a>
          <div className="flex items-center gap-3">
            <DarkModeToggle />
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-4 py-6">
        <CasesPage />
      </main>

      <footer className="border-t dark:border-neutral-900">
        <div className="mx-auto max-w-7xl px-4 py-6 text-xs text-neutral-500">
          © {new Date().getFullYear()} crimesense.ai
        </div>
      </footer>

      <Toaster richColors position="top-right" />
    </div>
  )
}

