export async function put_user_client_info() {
  console.log("put_user_client_info")
  const time_zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const locale = Intl.DateTimeFormat().resolvedOptions().locale;
  const body = { time_zone, locale };
  console.log(body);

  return fetch('/_user_client_info', {
    method: 'PUT',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
    .catch(error => console.error('`put_user_client_info` failed:', error));
}
