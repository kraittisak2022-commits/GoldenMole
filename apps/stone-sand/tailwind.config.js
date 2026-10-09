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
        page: 'rgb(var(--rgb-page) / <alpha-value>)',
        surface: 'rgb(var(--rgb-surface) / <alpha-value>)',
        ink: 'rgb(var(--rgb-ink) / <alpha-value>)',
        muted: 'rgb(var(--rgb-muted) / <alpha-value>)',
        subtle: 'rgb(var(--rgb-subtle) / <alpha-value>)',
        border: 'rgb(var(--rgb-border) / <alpha-value>)',
        primary: {
          DEFAULT: 'rgb(var(--rgb-primary) / <alpha-value>)',
          hover: 'rgb(var(--rgb-primary-hover) / <alpha-value>)',
          foreground: 'rgb(var(--rgb-primary-foreground) / <alpha-value>)',
          soft: 'rgb(var(--rgb-primary-soft) / <alpha-value>)',
        },
        success: {
          DEFAULT: 'rgb(var(--rgb-success) / <alpha-value>)',
          soft: 'rgb(var(--rgb-success-soft) / <alpha-value>)',
        },
        warning: {
          DEFAULT: 'rgb(var(--rgb-warning) / <alpha-value>)',
          soft: 'rgb(var(--rgb-warning-soft) / <alpha-value>)',
        },
        destructive: {
          DEFAULT: 'rgb(var(--rgb-destructive) / <alpha-value>)',
          foreground: 'rgb(var(--rgb-destructive-foreground) / <alpha-value>)',
          soft: 'rgb(var(--rgb-destructive-soft) / <alpha-value>)',
        },
        ring: 'rgb(var(--rgb-ring) / <alpha-value>)',
        stamp: 'rgb(var(--rgb-stamp) / <alpha-value>)',
      },
      fontFamily: {
        sans: ['"Noto Sans Thai"', 'Tahoma', 'sans-serif'],
      },
      borderRadius: {
        DEFAULT: '12px',
      },
      spacing: {
        'safe-top': 'env(safe-area-inset-top)',
        'safe-bottom': 'env(safe-area-inset-bottom)',
      },
      transitionDuration: {
        DEFAULT: '200ms',
      },
    },
  },
  plugins: [
    /**
     * `short:` targets phones in landscape. A raw-media screen would disable Tailwind's min-/max- variants;
     * `:root` keeps it winning over sm:/md:/lg: like a last-declared screen did.
     */
    ({ addVariant }) => addVariant('short', '@media (max-height: 500px) { :root & }'),
  ],
};
