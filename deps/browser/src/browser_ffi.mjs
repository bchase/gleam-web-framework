export async function put_user_client_info(path_prefix) {
  const time_zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const locale = Intl.DateTimeFormat().resolvedOptions().locale;
  const body = { time_zone, locale };

  const path = `/${path_prefix}/user_client_info`;

  return fetch(path, {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
    .catch(error => console.error('`put_user_client_info` failed:', error));
}
