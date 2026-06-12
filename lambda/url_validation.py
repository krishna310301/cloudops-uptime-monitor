import ipaddress
import socket
from urllib.parse import urlparse


BLOCKED_HOSTNAMES = {"localhost", "localhost.localdomain"}


def normalize_url(value):
    url = (value or "").strip()
    if not url:
        return ""

    if not url.startswith(("http://", "https://")):
        url = f"https://{url}"

    return url


def validate_monitor_url(value, resolve_host=False):
    try:
        parsed = urlparse(value)
    except Exception:
        return False, "URL could not be parsed"

    if parsed.scheme not in ("http", "https"):
        return False, "Only http and https URLs are supported"

    if not parsed.hostname:
        return False, "URL must include a hostname"

    if parsed.username or parsed.password:
        return False, "URL credentials are not supported"

    hostname = parsed.hostname.lower().rstrip(".")

    if hostname in BLOCKED_HOSTNAMES or hostname.endswith(".localhost"):
        return False, "Localhost targets are blocked"

    try:
        ip = ipaddress.ip_address(hostname)
    except ValueError:
        ip = None

    if ip and not is_public_ip(ip):
        return False, "Private, local, reserved, and metadata IP targets are blocked"

    if resolve_host and not ip:
        try:
            resolved_ips = resolve_hostname(hostname, parsed.port)
        except socket.gaierror:
            return False, "Hostname could not be resolved"

        if not resolved_ips:
            return False, "Hostname did not resolve to an address"

        if any(not is_public_ip(address) for address in resolved_ips):
            return False, "Hostname resolves to a private, local, reserved, or metadata address"

    return True, ""


def resolve_hostname(hostname, port):
    addresses = set()
    for result in socket.getaddrinfo(hostname, port, type=socket.SOCK_STREAM):
        sockaddr = result[4]
        addresses.add(ipaddress.ip_address(sockaddr[0]))

    return addresses


def is_public_ip(ip):
    return not (
        ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_multicast
        or ip.is_reserved
        or ip.is_unspecified
    )
