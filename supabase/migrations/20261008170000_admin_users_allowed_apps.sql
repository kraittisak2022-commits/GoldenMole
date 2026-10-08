-- Which websites an account may sign in to.
-- NULL keeps the role defaults: goldenmole.pro = every role, order = SuperAdmin/Admin, flowaccount = SuperAdmin.
-- Otherwise a list of site keys: 'main', 'order', 'flowaccount'.
ALTER TABLE admin_users ADD COLUMN IF NOT EXISTS allowed_apps TEXT[];
