/*
 * MacbyeDPI DNS Redirector
 * macOS port of goodbyeDPI's --dns-addr / --dns-port (dnsredir) feature.
 *
 * Listens for DNS queries on 127.0.0.1:53, transparently forwards them
 * to a configured upstream DNS server on any port, and returns responses
 * to the original caller — bypassing ISP DNS poisoning.
 *
 * Usage:
 *   sudo ./macbyedpi_dnsredir --dns-addr 77.88.8.8 --dns-port 1253
 *   sudo ./macbyedpi_dnsredir --dns-addr 8.8.8.8 --dns-port 53   (standard port)
 *
 * Then set your macOS DNS to 127.0.0.1 in:
 *   System Settings → Network → [your interface] → Details → DNS
 * Or run:  sudo ./setup.sh --dns-addr <IP> --dns-port <port>
 *
 * Build:   make
 * Requires: macOS 10.13+ (High Sierra), Xcode Command Line Tools
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <getopt.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>

/* -------------------------------------------------------------------------
 * Connection tracking table
 *
 * Maps remapped_query_id (uint16_t) → { original_id, client_addr, timestamp }
 *
 * We use a direct-indexed array of 65536 slots (keyed by uint16_t new_id)
 * giving O(1) lookup/insert/delete with no dynamic allocation or hash.
 * -------------------------------------------------------------------------*/

#define MAX_SLOTS     65536
#define CONN_TIMEOUT  30       /* seconds before a slot is recycled */
#define DNS_BUF_SIZE  4096     /* max DNS packet over UDP */
#define LISTEN_PORT   53

typedef struct {
    int      active;
    uint16_t orig_id;          /* query ID the client sent */
    struct sockaddr_storage client_addr;
    socklen_t               client_addrlen;
    time_t   timestamp;
} slot_t;

static slot_t   table[MAX_SLOTS];
static uint16_t next_id = 1;   /* rolling allocator; 0 is reserved */

/* Allocate the next available slot ID (skips 0, wraps at 65535→1). */
static uint16_t slot_alloc(void)
{
    uint16_t start = next_id;
    do {
        uint16_t id = next_id;
        /* Advance (wraps naturally for uint16_t; skip 0) */
        next_id = (next_id == 65535) ? 1 : next_id + 1;

        if (!table[id].active)
            return id;

        /* Reclaim timed-out slot */
        if (difftime(time(NULL), table[id].timestamp) > CONN_TIMEOUT) {
            table[id].active = 0;
            return id;
        }
    } while (next_id != start);

    return 0; /* table full — shouldn't happen in practice */
}

/* -------------------------------------------------------------------------
 * DNS helpers
 * -------------------------------------------------------------------------*/

/* Returns 1 if buf[0..len-1] looks like a DNS query (QR bit = 0). */
static int is_dns_query(const uint8_t *buf, ssize_t len)
{
    if (len < 12) return 0;
    /* Flags are at bytes 2-3 (network order). QR bit is the MSB of byte 2. */
    return (buf[2] & 0x80) == 0;
}

/* Returns 1 if buf[0..len-1] looks like a DNS response (QR bit = 1). */
static int is_dns_response(const uint8_t *buf, ssize_t len)
{
    if (len < 12) return 0;
    return (buf[2] & 0x80) != 0;
}

/* -------------------------------------------------------------------------
 * Globals
 * -------------------------------------------------------------------------*/
static volatile int g_running = 1;

static void sig_handler(int sig)
{
    (void)sig;
    g_running = 0;
}

/* -------------------------------------------------------------------------
 * Main
 * -------------------------------------------------------------------------*/
int main(int argc, char *argv[])
{
    const char *upstream_addr_str = NULL;
    uint16_t    upstream_port     = 53;
    const char *listen_addr_str   = "127.0.0.1";
    uint16_t    listen_port       = LISTEN_PORT;
    int         verbose           = 0;

    static const struct option long_opts[] = {
        { "dns-addr",    required_argument, NULL, 'a' },
        { "dns-port",    required_argument, NULL, 'p' },
        { "listen-addr", required_argument, NULL, 'l' },
        { "listen-port", required_argument, NULL, 'P' },
        { "verbose",     no_argument,       NULL, 'v' },
        { "help",        no_argument,       NULL, 'h' },
        { NULL, 0, NULL, 0 }
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "a:p:l:P:vh", long_opts, NULL)) != -1) {
        switch (opt) {
        case 'a': upstream_addr_str = optarg;                    break;
        case 'p': upstream_port     = (uint16_t)atoi(optarg);   break;
        case 'l': listen_addr_str   = optarg;                   break;
        case 'P': listen_port       = (uint16_t)atoi(optarg);   break;
        case 'v': verbose           = 1;                         break;
        case 'h':
        default:
            fprintf(stderr,
                "MacbyeDPI DNS Redirector — bypass ISP DNS poisoning on macOS\n"
                "\n"
                "Usage: sudo %s --dns-addr <IP> [options]\n"
                "\n"
                "Options:\n"
                "  --dns-addr   <IP>    Upstream DNS server IP (required)\n"
                "  --dns-port   <port>  Upstream DNS server port [default: 53]\n"
                "  --listen-addr <IP>   Local address to listen on [default: 127.0.0.1]\n"
                "  --listen-port <port> Local port to listen on [default: 53]\n"
                "  --verbose            Print each redirected query\n"
                "  --help               Show this help\n"
                "\n"
                "Examples:\n"
                "  sudo %s --dns-addr 77.88.8.8 --dns-port 1253\n"
                "  sudo %s --dns-addr 8.8.8.8   --dns-port 53\n"
                "  sudo %s --dns-addr 1.1.1.1   --dns-port 53\n"
                "\n"
                "After starting, set your Mac's DNS to 127.0.0.1:\n"
                "  sudo networksetup -setdnsservers Wi-Fi 127.0.0.1\n",
                argv[0], argv[0], argv[0], argv[0]);
            return opt == 'h' ? 0 : 1;
        }
    }

    if (!upstream_addr_str) {
        fprintf(stderr, "Error: --dns-addr is required.\n"
                        "Run '%s --help' for usage.\n", argv[0]);
        return 1;
    }

    /* Validate upstream address */
    struct in_addr upstream_in;
    if (inet_pton(AF_INET, upstream_addr_str, &upstream_in) != 1) {
        fprintf(stderr, "Error: invalid --dns-addr '%s'\n", upstream_addr_str);
        return 1;
    }

    /* ---- Signal handling ---- */
    signal(SIGINT,  sig_handler);
    signal(SIGTERM, sig_handler);

    /* ---- Listening socket (receives client queries) ---- */
    int listen_fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (listen_fd < 0) { perror("socket(listen)"); return 1; }

    {
        int yes = 1;
        setsockopt(listen_fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
        setsockopt(listen_fd, SOL_SOCKET, SO_REUSEPORT, &yes, sizeof(yes));
    }

    struct sockaddr_in listen_sa = {0};
    listen_sa.sin_family      = AF_INET;
    listen_sa.sin_port        = htons(listen_port);
    inet_pton(AF_INET, listen_addr_str, &listen_sa.sin_addr);

    if (bind(listen_fd, (struct sockaddr *)&listen_sa, sizeof(listen_sa)) < 0) {
        perror("bind");
        if (errno == EACCES)
            fprintf(stderr,
                "Hint: port %d requires root privileges. Run with sudo.\n",
                listen_port);
        if (errno == EADDRINUSE)
            fprintf(stderr,
                "Hint: port %d is already in use. "
                "Use --listen-port to choose another, then add a pf redirect rule.\n",
                listen_port);
        close(listen_fd);
        return 1;
    }

    /* ---- Upstream socket (talks to the real DNS server) ---- */
    int upstream_fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (upstream_fd < 0) { perror("socket(upstream)"); close(listen_fd); return 1; }

    struct sockaddr_in upstream_sa = {0};
    upstream_sa.sin_family = AF_INET;
    upstream_sa.sin_port   = htons(upstream_port);
    memcpy(&upstream_sa.sin_addr, &upstream_in, sizeof(upstream_in));

    /* ---- Ready ---- */
    printf("MacbyeDPI DNS Redirector started\n");
    printf("Listening : %s:%d\n", listen_addr_str, listen_port);
    printf("Upstream  : %s:%d\n", upstream_addr_str, upstream_port);
    printf("Press Ctrl+C to stop.\n\n");

    memset(table, 0, sizeof(table));

    uint8_t buf[DNS_BUF_SIZE];

    while (g_running) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET(listen_fd,   &rfds);
        FD_SET(upstream_fd, &rfds);
        int maxfd = (listen_fd > upstream_fd) ? listen_fd : upstream_fd;

        struct timeval tv = { .tv_sec = 2, .tv_usec = 0 };
        int n = select(maxfd + 1, &rfds, NULL, NULL, &tv);
        if (n < 0) {
            if (errno == EINTR) continue;
            perror("select");
            break;
        }

        /* ---- Incoming client query → forward to upstream ---- */
        if (FD_ISSET(listen_fd, &rfds)) {
            struct sockaddr_storage client_sa;
            socklen_t client_len = sizeof(client_sa);

            ssize_t len = recvfrom(listen_fd, buf, sizeof(buf), 0,
                                   (struct sockaddr *)&client_sa, &client_len);
            if (len < 12) goto handle_upstream;

            if (!is_dns_query(buf, len)) goto handle_upstream;

            uint16_t orig_id;
            memcpy(&orig_id, buf, 2); /* network byte order — keep as-is for memcmp */

            /* Allocate a slot and remap the query ID */
            uint16_t new_id = slot_alloc();
            if (new_id == 0) {
                fprintf(stderr, "Warning: connection table full, dropping query.\n");
                goto handle_upstream;
            }

            table[new_id].active         = 1;
            table[new_id].orig_id        = orig_id;
            table[new_id].client_addrlen = client_len;
            memcpy(&table[new_id].client_addr, &client_sa, client_len);
            table[new_id].timestamp      = time(NULL);

            /* Patch the query ID in the packet */
            uint16_t new_id_net = htons(new_id);
            memcpy(buf, &new_id_net, 2);

            ssize_t sent = sendto(upstream_fd, buf, len, 0,
                                  (struct sockaddr *)&upstream_sa,
                                  sizeof(upstream_sa));
            if (sent < 0 && verbose)
                perror("sendto(upstream)");

            if (verbose) {
                char client_ip[INET6_ADDRSTRLEN] = "?";
                if (client_sa.ss_family == AF_INET)
                    inet_ntop(AF_INET,
                              &((struct sockaddr_in *)&client_sa)->sin_addr,
                              client_ip, sizeof(client_ip));
                printf("[→] query  id=0x%04x→0x%04x  from %s\n",
                       ntohs(orig_id), new_id, client_ip);
            }
        }

    handle_upstream:
        /* ---- Upstream response → forward back to original client ---- */
        if (FD_ISSET(upstream_fd, &rfds)) {
            ssize_t len = recv(upstream_fd, buf, sizeof(buf), 0);
            if (len < 12) continue;

            if (!is_dns_response(buf, len)) continue;

            uint16_t resp_id_net;
            memcpy(&resp_id_net, buf, 2);
            uint16_t resp_id = ntohs(resp_id_net);

            if (!table[resp_id].active) {
                /* Unknown/timed-out response — discard */
                if (verbose) printf("[!] unknown response id=0x%04x, dropped\n", resp_id);
                continue;
            }

            /* Restore original client query ID */
            memcpy(buf, &table[resp_id].orig_id, 2);

            ssize_t sent = sendto(listen_fd, buf, len, 0,
                                  (struct sockaddr *)&table[resp_id].client_addr,
                                  table[resp_id].client_addrlen);
            if (sent < 0 && verbose)
                perror("sendto(client)");

            if (verbose) {
                char client_ip[INET6_ADDRSTRLEN] = "?";
                struct sockaddr_storage *sa = &table[resp_id].client_addr;
                if (sa->ss_family == AF_INET)
                    inet_ntop(AF_INET,
                              &((struct sockaddr_in *)sa)->sin_addr,
                              client_ip, sizeof(client_ip));
                printf("[←] response id=0x%04x  to   %s\n", resp_id, client_ip);
            }

            /* Free the slot */
            table[resp_id].active = 0;
        }
    }

    /* ---- Clean shutdown ---- */
    printf("\nShutting down.\n");
    close(listen_fd);
    close(upstream_fd);
    return 0;
}
