export const API_BASE_URL = 'http://127.0.0.1:8000';
const EVENTS_URL = import.meta.env?.DEV
  ? '/api/events'
  : `${API_BASE_URL}/events`;

const SEVERITIES = new Set(['critical', 'high', 'medium', 'low']);

const toFiniteNumber = (value, fallback = 0) => {
  if (value === null || value === undefined || value === '') return fallback;
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
};

const deriveSeverity = (eventType, confidence) => {
  if (eventType === 'pothole') {
    if (confidence >= 0.6) return 'critical';
    if (confidence >= 0.35) return 'high';
    return 'medium';
  }

  if (eventType === 'alligator_crack') {
    return confidence >= 0.5 ? 'high' : 'medium';
  }

  if (eventType === 'longitudinal_crack' || eventType === 'transverse_crack') {
    return confidence >= 0.35 ? 'medium' : 'low';
  }

  return confidence >= 0.75 ? 'high' : 'low';
};

export const normalizeEvent = (event) => {
  const eventType = String(event?.event_type || 'other').toLowerCase();
  const confidence = Math.min(Math.max(toFiniteNumber(event?.confidence), 0), 1);
  const suppliedSeverity = String(event?.severity || '').toLowerCase();

  return {
    ...event,
    event_type: eventType,
    confidence,
    severity: SEVERITIES.has(suppliedSeverity)
      ? suppliedSeverity
      : deriveSeverity(eventType, confidence),
    status: String(event?.status || 'pending').toLowerCase(),
    latitude: toFiniteNumber(event?.latitude, Number.NaN),
    longitude: toFiniteNumber(event?.longitude, Number.NaN),
    source: event?.source || 'camera',
  };
};

export const hasValidCoordinates = ({ latitude, longitude }) => (
  Number.isFinite(latitude)
  && Number.isFinite(longitude)
  && latitude >= -90
  && latitude <= 90
  && longitude >= -180
  && longitude <= 180
);

export async function getEvents({ signal } = {}) {
  let response;

  try {
    response = await fetch(EVENTS_URL, {
      headers: { Accept: 'application/json' },
      signal,
    });
  } catch (error) {
    if (error?.name === 'AbortError') throw error;
    throw new Error('Unable to reach the UrbanEye backend.', { cause: error });
  }

  if (!response.ok) {
    throw new Error(`UrbanEye backend returned ${response.status}.`);
  }

  const events = await response.json();
  if (!Array.isArray(events)) {
    throw new Error('UrbanEye backend returned an invalid events response.');
  }

  return events
    .map(normalizeEvent)
    .sort((first, second) => new Date(second.timestamp) - new Date(first.timestamp));
}

export async function updateEventStatus(eventId, status) {
  const response = await fetch(`${EVENTS_URL}/${eventId}/status`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
    body: JSON.stringify({ status })
  });

  if (!response.ok) {
    throw new Error('Failed to update event status');
  }

  return response.json();
}
