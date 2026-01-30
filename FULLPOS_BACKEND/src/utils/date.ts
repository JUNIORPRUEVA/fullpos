import { isAfter, isBefore } from 'date-fns';
import { fromZonedTime } from 'date-fns-tz';

function getReportsTimeZone() {
  return process.env.REPORTS_TIMEZONE || 'America/Santo_Domingo';
}

export function parseRange(from: string, to: string) {
  // Interpret YYYY-MM-DD as a business-local date (not server local timezone).
  // This keeps ranges consistent across deployments/servers.
  const timeZone = getReportsTimeZone();
  const fromDate = fromZonedTime(`${from}T00:00:00.000`, timeZone);
  const toDate = fromZonedTime(`${to}T23:59:59.999`, timeZone);

  if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) {
    throw new Error('Rango de fechas inv\u00e1lido');
  }

  if (isAfter(fromDate, toDate)) {
    throw new Error('from must be before or equal to to');
  }

  return { fromDate, toDate };
}

export function ensureRangeWithinDays(fromDate: Date, toDate: Date, maxDays: number) {
  const limitDate = new Date(fromDate);
  limitDate.setDate(limitDate.getDate() + maxDays);
  if (isBefore(limitDate, toDate)) {
    throw new Error(`Range cannot exceed ${maxDays} days`);
  }
}
