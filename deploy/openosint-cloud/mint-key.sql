-- Create one API key for yourself. Run after db/init.sql:
--   heroku pg:psql -a <app> -f deploy/openosint-cloud/mint-key.sql
--
-- Generate a key first and paste it in below:
--   python3 -c "import secrets; print(secrets.token_urlsafe(32))"
--
-- credits are decremented per tool call; top up by updating the column.

INSERT INTO customers (api_key, credits, plan)
VALUES ('REPLACE_WITH_GENERATED_KEY', 100000, 'pro')
ON CONFLICT (api_key) DO UPDATE SET credits = EXCLUDED.credits;

SELECT api_key, credits, plan FROM customers;
