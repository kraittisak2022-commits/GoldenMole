import { FormEvent, useEffect, useRef, useState } from 'react';
import { LockKeyhole } from 'lucide-react';
import { saveAlbumAccess } from '../lib/albumAccess';
import { api, errorCode } from '../lib/api';
import { errorMessage } from '../lib/errors';
import Button from './ui/Button';

const PIN_LENGTH = 4;

/** Asks for the album PIN before anything about the album (even its title) is shown. */
export default function PinGate({ shareToken, onUnlocked }: { shareToken: string; onUnlocked: () => void }) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [pin, setPin] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [locked, setLocked] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => inputRef.current?.focus(), []);

  const submit = async (value: string) => {
    if (value.length !== PIN_LENGTH || busy || locked) return;
    setBusy(true);
    setError(null);
    try {
      const { access } = await api<{ access: string }>(`/api/share/${encodeURIComponent(shareToken)}`, { method: 'POST', body: { pin: value } });
      saveAlbumAccess(shareToken, access);
      onUnlocked();
    } catch (err) {
      setError(errorMessage(err));
      setLocked(errorCode(err) === 'too_many_attempts');
      setPin('');
      inputRef.current?.focus();
    } finally {
      setBusy(false);
    }
  };

  const onChange = (raw: string) => {
    const digits = raw.replace(/\D/g, '').slice(0, PIN_LENGTH);
    setPin(digits);
    if (digits.length === PIN_LENGTH) void submit(digits);
  };

  const onSubmit = (e: FormEvent) => {
    e.preventDefault();
    void submit(pin);
  };

  return (
    <main className="mx-auto flex min-h-[70dvh] max-w-sm flex-col items-center justify-center px-6 py-12 text-center">
      <span className="flex h-16 w-16 items-center justify-center rounded-full bg-primary-soft text-primary-soft-foreground">
        <LockKeyhole size={30} aria-hidden />
      </span>
      <h1 className="mt-5 text-2xl font-normal text-ink">อัลบั้มนี้ป้องกันด้วย PIN</h1>
      <p className="mt-2 text-sm text-muted">ใส่ PIN {PIN_LENGTH} หลักที่ได้รับจากทีมงาน เพื่อดูและเพิ่มรูป</p>

      <form onSubmit={onSubmit} className="mt-8 w-full">
        <label className="relative mx-auto flex w-fit cursor-text gap-3">
          <span className="sr-only">PIN</span>
          {Array.from({ length: PIN_LENGTH }, (_, i) => (
            <span
              key={i}
              aria-hidden
              className={[
                'flex h-14 w-12 items-center justify-center rounded-xl border-2 text-2xl transition',
                error ? 'border-destructive' : i === pin.length && !busy ? 'border-primary' : 'border-border',
              ].join(' ')}
            >
              {i < pin.length ? '•' : ''}
            </span>
          ))}
          <input
            ref={inputRef}
            value={pin}
            onChange={(e) => onChange(e.target.value)}
            inputMode="numeric"
            pattern="[0-9]*"
            autoComplete="off"
            enterKeyHint="go"
            maxLength={PIN_LENGTH}
            disabled={busy || locked}
            aria-invalid={!!error}
            aria-describedby={error ? 'pin-error' : undefined}
            className="absolute inset-0 h-full w-full cursor-text opacity-0"
          />
        </label>
        <p id="pin-error" role="alert" className="mt-4 min-h-5 text-sm text-destructive">
          {error}
        </p>
        <Button type="submit" disabled={pin.length !== PIN_LENGTH || busy || locked} className="mt-4 w-full">
          {busy ? 'กำลังตรวจสอบ…' : 'เปิดอัลบั้ม'}
        </Button>
      </form>
    </main>
  );
}
