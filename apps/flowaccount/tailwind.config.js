/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    screens: {
      xs: '375px',
      sm: '640px',
      md: '768px',
      lg: '1024px',
      xl: '1280px',
      '2xl': '1536px',
    },
    extend: {
      colors: {
        page: 'var(--color-page)',
        surface: 'var(--color-surface)',
        ink: 'var(--color-ink)',
        muted: 'var(--color-muted)',
        border: 'var(--color-border)',
        accent: {
          DEFAULT: 'var(--color-accent)',
          foreground: 'var(--color-accent-foreground)',
        },
        destructive: {
          DEFAULT: 'var(--color-destructive)',
          foreground: 'var(--color-destructive-foreground)',
        },
        ring: 'var(--color-ring)',
        gold: 'var(--color-gold)',
      },
      fontFamily: {
        sans: ['Kanit', 'Prompt', 'Noto Sans Thai', 'Tahoma', 'sans-serif'],
      },
      borderRadius: {
        DEFAULT: '8px',
      },
      spacing: {
        'safe-top': 'env(safe-area-inset-top)',
        'safe-bottom': 'env(safe-area-inset-bottom)',
        'safe-left': 'env(safe-area-inset-left)',
        'safe-right': 'env(safe-area-inset-right)',
      },
      transitionDuration: {
        DEFAULT: '200ms',
      },
      keyframes: {
        'login-float': {
          '0%, 100%': { transform: 'translateY(0)' },
          '50%': { transform: 'translateY(-8px)' },
        },
        'login-aurora': {
          '0%, 100%': { transform: 'translate(0, 0) scale(1)', opacity: '0.55' },
          '33%': { transform: 'translate(12px, -18px) scale(1.06)', opacity: '0.7' },
          '66%': { transform: 'translate(-10px, 10px) scale(0.96)', opacity: '0.5' },
        },
        'login-shimmer': {
          '0%': { backgroundPosition: '200% 0' },
          '100%': { backgroundPosition: '-200% 0' },
        },
        'login-shake': {
          '0%, 100%': { transform: 'translateX(0)' },
          '15%': { transform: 'translateX(-6px)' },
          '30%': { transform: 'translateX(6px)' },
          '45%': { transform: 'translateX(-4px)' },
          '60%': { transform: 'translateX(4px)' },
          '75%': { transform: 'translateX(-2px)' },
        },
        'login-keystroke': {
          '0%': {
            boxShadow: '0 0 0 0 rgba(3, 105, 161, 0.28)',
            opacity: '0.85',
          },
          '100%': {
            boxShadow: '0 0 0 10px rgba(3, 105, 161, 0)',
            opacity: '0',
          },
        },
        'login-scan': {
          '0%': { top: '-5%', opacity: '0' },
          '8%': { opacity: '1' },
          '92%': { opacity: '1' },
          '100%': { top: '105%', opacity: '0' },
        },
        'login-enter': {
          from: { opacity: '0', transform: 'translateY(16px)' },
          to: { opacity: '1', transform: 'translateY(0)' },
        },
      },
      animation: {
        'login-float': 'login-float 5s ease-in-out infinite',
        'login-float-slow': 'login-float 7s ease-in-out infinite',
        'login-aurora': 'login-aurora 14s ease-in-out infinite',
        'login-aurora-delayed': 'login-aurora 18s ease-in-out 2s infinite',
        'login-shimmer': 'login-shimmer 2.8s linear infinite',
        'login-shake': 'login-shake 0.55s ease-in-out',
        'login-keystroke': 'login-keystroke 0.45s ease-out forwards',
        'login-scan': 'login-scan 6s ease-in-out infinite',
        'login-enter': 'login-enter 0.7s ease-out both',
      },
    },
  },
  plugins: [],
};
