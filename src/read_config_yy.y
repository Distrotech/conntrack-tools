%{
/*
 * (C) 2006-2009 by Pablo Neira Ayuso <pablo@netfilter.org>
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * Description: configuration file abstract grammar
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <netdb.h>
#include <errno.h>
#include <stdarg.h>
#include "conntrackd.h"
#include "bitops.h"
#include "cidr.h"
#include "helper.h"
#include "stack.h"
#include <syslog.h>
#include <sched.h>
#include <dlfcn.h>
#include <libnetfilter_conntrack/libnetfilter_conntrack.h>
#include <libnetfilter_conntrack/libnetfilter_conntrack_tcp.h>

extern char *yytext;
extern int   yylineno;

struct ct_conf conf;

enum {
	CTD_CFG_ERROR = 0,
	CTD_CFG_WARN,
};

static void print_err(int err, const char *msg, ...);

static void __kernel_filter_start(void);
static void __kernel_filter_add_state(int value);
static void __max_dedicated_links_reached(void);

struct stack symbol_stack;

enum {
	SYMBOL_HELPER_QUEUE_NUM,
	SYMBOL_HELPER_QUEUE_LEN,
	SYMBOL_HELPER_POLICY_EXPECT_ROOT,
	SYMBOL_HELPER_EXPECT_POLICY_LEAF,
};

%}

%union {
	int		val;
	char		*string;
}

%token T_IPV4_ADDR T_IPV4_IFACE T_PORT T_HASHSIZE T_HASHLIMIT T_MULTICAST
%token T_PATH T_UNIX T_REFRESH T_IPV6_ADDR T_IPV6_IFACE
%token T_IGNORE_UDP T_IGNORE_ICMP T_IGNORE_TRAFFIC T_BACKLOG T_GROUP
%token T_LOG T_UDP T_ICMP T_IGMP T_VRRP T_TCP T_IGNORE_PROTOCOL
%token T_LOCK T_STRIP_NAT T_BUFFER_SIZE_MAX_GROWN T_EXPIRE T_TIMEOUT
%token T_GENERAL T_SYNC T_STATS T_RELAX_TRANSITIONS T_BUFFER_SIZE T_DELAY
%token T_SYNC_MODE T_LISTEN_TO T_FAMILY T_RESEND_BUFFER_SIZE
%token T_ALARM T_FTFW T_CHECKSUM T_WINDOWSIZE T_ON T_OFF
%token T_REPLICATE T_FOR T_IFACE T_PURGE T_RESEND_QUEUE_SIZE
%token T_ESTABLISHED T_SYN_SENT T_SYN_RECV T_FIN_WAIT 
%token T_CLOSE_WAIT T_LAST_ACK T_TIME_WAIT T_CLOSE T_LISTEN
%token T_SYSLOG T_WRITE_THROUGH T_STAT_BUFFER_SIZE T_DESTROY_TIMEOUT
%token T_RCVBUFF T_SNDBUFF T_NOTRACK T_POLL_SECS
%token T_FILTER T_ADDRESS T_PROTOCOL T_STATE T_ACCEPT T_IGNORE
%token T_FROM T_USERSPACE T_KERNELSPACE T_EVENT_ITER_LIMIT T_DEFAULT
%token T_NETLINK_OVERRUN_RESYNC T_NICE T_IPV4_DEST_ADDR T_IPV6_DEST_ADDR
%token T_SCHEDULER T_TYPE T_PRIO T_NETLINK_EVENTS_RELIABLE
%token T_DISABLE_INTERNAL_CACHE T_DISABLE_EXTERNAL_CACHE T_ERROR_QUEUE_LENGTH
%token T_OPTIONS T_TCP_WINDOW_TRACKING T_EXPECT_SYNC
%token T_HELPER T_HELPER_QUEUE_NUM T_HELPER_QUEUE_LEN T_HELPER_POLICY
%token T_HELPER_EXPECT_TIMEOUT T_HELPER_EXPECT_MAX

%token <string> T_IP T_PATH_VAL
%token <val> T_NUMBER
%token <val> T_SIGNED_NUMBER
%token <string> T_STRING

%%

configfile :
	   | lines
	   ;

lines : line
      | lines line
      ;

line : ignore_protocol
     | ignore_traffic
     | strip_nat
     | general
     | sync
     | stats
     | helper
     ;

logfile_bool : T_LOG T_ON
{
	strncpy(conf.logfile, DEFAULT_LOGFILE, FILENAME_MAXLEN);
};

logfile_bool : T_LOG T_OFF
{
};

logfile_path : T_LOG T_PATH_VAL
{
	strncpy(conf.logfile, $2, FILENAME_MAXLEN);
};

syslog_bool : T_SYSLOG T_ON
{
	conf.syslog_facility = DEFAULT_SYSLOG_FACILITY;
};

syslog_bool : T_SYSLOG T_OFF
{
	conf.syslog_facility = -1;
}

syslog_facility : T_SYSLOG T_STRING
{
	if (!strcmp($2, "daemon"))
		conf.syslog_facility = LOG_DAEMON;
	else if (!strcmp($2, "local0"))
		conf.syslog_facility = LOG_LOCAL0;
	else if (!strcmp($2, "local1"))
		conf.syslog_facility = LOG_LOCAL1;
	else if (!strcmp($2, "local2"))
		conf.syslog_facility = LOG_LOCAL2;
	else if (!strcmp($2, "local3"))
		conf.syslog_facility = LOG_LOCAL3;
	else if (!strcmp($2, "local4"))
		conf.syslog_facility = LOG_LOCAL4;
	else if (!strcmp($2, "local5"))
		conf.syslog_facility = LOG_LOCAL5;
	else if (!strcmp($2, "local6"))
		conf.syslog_facility = LOG_LOCAL6;
	else if (!strcmp($2, "local7"))
		conf.syslog_facility = LOG_LOCAL7;
	else {
		print_err(CTD_CFG_WARN, "'%s' is not a known syslog facility, "
					"ignoring", $2);
		break;
	}

	if (conf.stats.syslog_facility != -1 &&
	    conf.syslog_facility != conf.stats.syslog_facility)
	    	print_err(CTD_CFG_WARN, "conflicting Syslog facility "
					"values, defaulting to General");
};

lock : T_LOCK T_PATH_VAL
{
	strncpy(conf.lockfile, $2, FILENAME_MAXLEN);
};

strip_nat: T_STRIP_NAT
{
	print_err(CTD_CFG_WARN, "`StripNAT' clause is obsolete, ignoring");
};

refreshtime : T_REFRESH T_NUMBER
{
	conf.refresh = $2;
};

expiretime: T_EXPIRE T_NUMBER
{
	conf.cache_timeout = $2;
};

timeout: T_TIMEOUT T_NUMBER
{
	conf.commit_timeout = $2;
};

purge: T_PURGE T_NUMBER
{
	conf.purge_timeout = $2;
};

checksum: T_CHECKSUM T_ON 
{
	print_err(CTD_CFG_WARN, "the use of `Checksum' outside the "
				"`Multicast' clause is ambiguous");
	/* 
	 * XXX: The use of Checksum outside of the Multicast clause is broken
	 *	if we have more than one dedicated links.
	 */
	conf.channel[0].u.mcast.checksum = 0;
};

checksum: T_CHECKSUM T_OFF
{
	print_err(CTD_CFG_WARN, "the use of `Checksum' outside the "
				"`Multicast' clause is ambiguous");
	/*
	 * XXX: The use of Checksum outside of the Multicast clause is broken
	 *	if we have more than one dedicated links.
	 */
	conf.channel[0].u.mcast.checksum = 1;
};

ignore_traffic : T_IGNORE_TRAFFIC '{' ignore_traffic_options '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_ADDRESS,
			    CT_FILTER_NEGATIVE);

	print_err(CTD_CFG_WARN, "the clause `IgnoreTrafficFor' is obsolete. "
				"Use `Filter' instead");
};

ignore_traffic_options :
		       | ignore_traffic_options ignore_traffic_option;

ignore_traffic_option : T_IPV4_ADDR T_IP
{
	union inet_address ip;

	memset(&ip, 0, sizeof(union inet_address));

	if (!inet_aton($2, &ip.ipv4)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4, "
					"ignoring", $2);
		break;
	}

	if (!ct_filter_add_ip(STATE(us_filter), &ip, AF_INET)) {
		if (errno == EEXIST)
			print_err(CTD_CFG_WARN, "IP %s is repeated "
						"in the ignore pool", $2);
		if (errno == ENOSPC)
			print_err(CTD_CFG_WARN, "too many IP in the "
						"ignore pool!");
	}
};

ignore_traffic_option : T_IPV6_ADDR T_IP
{
	union inet_address ip;

	memset(&ip, 0, sizeof(union inet_address));

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2, &ip.ipv6) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6, ignoring", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
#endif

	if (!ct_filter_add_ip(STATE(us_filter), &ip, AF_INET6)) {
		if (errno == EEXIST)
			print_err(CTD_CFG_WARN, "IP %s is repeated "
						"in the ignore pool", $2);
		if (errno == ENOSPC)
			print_err(CTD_CFG_WARN, "too many IP in the "
						"ignore pool!");
	}

};

multicast_line : T_MULTICAST '{' multicast_options '}'
{
	if (conf.channel_type_global != CHANNEL_NONE &&
	    conf.channel_type_global != CHANNEL_MCAST) {
		print_err(CTD_CFG_ERROR, "cannot use `Multicast' with other "
					 "dedicated link protocols!");
		exit(EXIT_FAILURE);
	}
	conf.channel_type_global = CHANNEL_MCAST;
	conf.channel[conf.channel_num].channel_type = CHANNEL_MCAST;
	conf.channel[conf.channel_num].channel_flags = CHANNEL_F_BUFFERED;
	conf.channel_num++;
};

multicast_line : T_MULTICAST T_DEFAULT '{' multicast_options '}'
{
	if (conf.channel_type_global != CHANNEL_NONE &&
	    conf.channel_type_global != CHANNEL_MCAST) {
		print_err(CTD_CFG_ERROR, "cannot use `Multicast' with other "
					 "dedicated link protocols!");
		exit(EXIT_FAILURE);
	}
	conf.channel_type_global = CHANNEL_MCAST;
	conf.channel[conf.channel_num].channel_type = CHANNEL_MCAST;
	conf.channel[conf.channel_num].channel_flags = CHANNEL_F_DEFAULT |
						       CHANNEL_F_BUFFERED;
	conf.channel_default = conf.channel_num;
	conf.channel_num++;
};

multicast_options :
		  | multicast_options multicast_option;

multicast_option : T_IPV4_ADDR T_IP
{
	__max_dedicated_links_reached();

	if (!inet_aton($2, &conf.channel[conf.channel_num].u.mcast.in)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4 address", $2);
		break;
	}

        if (conf.channel[conf.channel_num].u.mcast.ipproto == AF_INET6) {
		print_err(CTD_CFG_WARN, "your multicast address is IPv4 but "
					"is binded to an IPv6 interface? "
					"Surely, this is not what you want");
		break;
	}

	conf.channel[conf.channel_num].u.mcast.ipproto = AF_INET;
};

multicast_option : T_IPV6_ADDR T_IP
{
	__max_dedicated_links_reached();

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2,
		      &conf.channel[conf.channel_num].u.mcast.in) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6 address", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
	break;
#endif

	if (conf.channel[conf.channel_num].u.mcast.ipproto == AF_INET) {
		print_err(CTD_CFG_WARN, "your multicast address is IPv6 but "
					"is binded to an IPv4 interface? "
					"Surely this is not what you want");
		break;
	}

	conf.channel[conf.channel_num].u.mcast.ipproto = AF_INET6;

	if (conf.channel[conf.channel_num].channel_ifname[0] &&
	    !conf.channel[conf.channel_num].u.mcast.ifa.interface_index6) {
		unsigned int idx;

		idx = if_nametoindex($2);
		if (!idx) {
			print_err(CTD_CFG_WARN,
				  "%s is an invalid interface", $2);
			break;
		}

		conf.channel[conf.channel_num].u.mcast.ifa.interface_index6 = idx;
		conf.channel[conf.channel_num].u.mcast.ipproto = AF_INET6;
	}
};

multicast_option : T_IPV4_IFACE T_IP
{
	__max_dedicated_links_reached();

	if (!inet_aton($2, &conf.channel[conf.channel_num].u.mcast.ifa)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4 address", $2);
		break;
	}

        if (conf.channel[conf.channel_num].u.mcast.ipproto == AF_INET6) {
		print_err(CTD_CFG_WARN, "your multicast interface is IPv4 but "
					"is binded to an IPv6 interface? "
					"Surely, this is not what you want");
		break;
	}

	conf.channel[conf.channel_num].u.mcast.ipproto = AF_INET;
};

multicast_option : T_IPV6_IFACE T_IP
{
	print_err(CTD_CFG_WARN, "`IPv6_interface' not required, ignoring");
}

multicast_option : T_IFACE T_STRING
{
	unsigned int idx;

	__max_dedicated_links_reached();

	strncpy(conf.channel[conf.channel_num].channel_ifname, $2, IFNAMSIZ);

	idx = if_nametoindex($2);
	if (!idx) {
		print_err(CTD_CFG_WARN, "%s is an invalid interface", $2);
		break;
	}

	if (conf.channel[conf.channel_num].u.mcast.ipproto == AF_INET6) {
		conf.channel[conf.channel_num].u.mcast.ifa.interface_index6 = idx;
		conf.channel[conf.channel_num].u.mcast.ipproto = AF_INET6;
	}
};

multicast_option : T_BACKLOG T_NUMBER
{
	print_err(CTD_CFG_WARN, "`Backlog' option inside Multicast clause is "
				"obsolete. Please, remove it from "
				"conntrackd.conf");
};

multicast_option : T_GROUP T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.mcast.port = $2;
};

multicast_option: T_SNDBUFF T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.mcast.sndbuf = $2;
};

multicast_option: T_RCVBUFF T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.mcast.rcvbuf = $2;
};

multicast_option: T_CHECKSUM T_ON 
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.mcast.checksum = 0;
};

multicast_option: T_CHECKSUM T_OFF
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.mcast.checksum = 1;
};

udp_line : T_UDP '{' udp_options '}'
{
	if (conf.channel_type_global != CHANNEL_NONE &&
	    conf.channel_type_global != CHANNEL_UDP) {
		print_err(CTD_CFG_ERROR, "cannot use `UDP' with other "
					 "dedicated link protocols!");
		exit(EXIT_FAILURE);
	}
	conf.channel_type_global = CHANNEL_UDP;
	conf.channel[conf.channel_num].channel_type = CHANNEL_UDP;
	conf.channel[conf.channel_num].channel_flags = CHANNEL_F_BUFFERED;
	conf.channel_num++;
};

udp_line : T_UDP T_DEFAULT '{' udp_options '}'
{
	if (conf.channel_type_global != CHANNEL_NONE &&
	    conf.channel_type_global != CHANNEL_UDP) {
		print_err(CTD_CFG_ERROR, "cannot use `UDP' with other "
					 "dedicated link protocols!");
		exit(EXIT_FAILURE);
	}
	conf.channel_type_global = CHANNEL_UDP;
	conf.channel[conf.channel_num].channel_type = CHANNEL_UDP;
	conf.channel[conf.channel_num].channel_flags = CHANNEL_F_DEFAULT |
						       CHANNEL_F_BUFFERED;
	conf.channel_default = conf.channel_num;
	conf.channel_num++;
};

udp_options :
	    | udp_options udp_option;

udp_option : T_IPV4_ADDR T_IP
{
	__max_dedicated_links_reached();

	if (!inet_aton($2, &conf.channel[conf.channel_num].u.udp.server.ipv4)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4 address", $2);
		break;
	}
	conf.channel[conf.channel_num].u.udp.ipproto = AF_INET;
};

udp_option : T_IPV6_ADDR T_IP
{
	__max_dedicated_links_reached();

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2,
		      &conf.channel[conf.channel_num].u.udp.server.ipv6) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6 address", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
	break;
#endif
	conf.channel[conf.channel_num].u.udp.ipproto = AF_INET6;
};

udp_option : T_IPV4_DEST_ADDR T_IP
{
	__max_dedicated_links_reached();

	if (!inet_aton($2, &conf.channel[conf.channel_num].u.udp.client)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4 address", $2);
		break;
	}
	conf.channel[conf.channel_num].u.udp.ipproto = AF_INET;
};

udp_option : T_IPV6_DEST_ADDR T_IP
{
	__max_dedicated_links_reached();

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2,
		      &conf.channel[conf.channel_num].u.udp.client) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6 address", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
	break;
#endif
	conf.channel[conf.channel_num].u.udp.ipproto = AF_INET6;
};

udp_option : T_IFACE T_STRING
{
	int idx;

	__max_dedicated_links_reached();
	strncpy(conf.channel[conf.channel_num].channel_ifname, $2, IFNAMSIZ);

	idx = if_nametoindex($2);
	if (!idx) {
		print_err(CTD_CFG_WARN, "%s is an invalid interface", $2);
		break;
	}
	conf.channel[conf.channel_num].u.udp.server.ipv6.scope_id = idx;
};

udp_option : T_PORT T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.udp.port = $2;
};

udp_option: T_SNDBUFF T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.udp.sndbuf = $2;
};

udp_option: T_RCVBUFF T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.udp.rcvbuf = $2;
};

udp_option: T_CHECKSUM T_ON 
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.udp.checksum = 0;
};

udp_option: T_CHECKSUM T_OFF
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.udp.checksum = 1;
};

tcp_line : T_TCP '{' tcp_options '}'
{
	if (conf.channel_type_global != CHANNEL_NONE &&
	    conf.channel_type_global != CHANNEL_TCP) {
		print_err(CTD_CFG_ERROR, "cannot use `TCP' with other "
					 "dedicated link protocols!");
		exit(EXIT_FAILURE);
	}
	conf.channel_type_global = CHANNEL_TCP;
	conf.channel[conf.channel_num].channel_type = CHANNEL_TCP;
	conf.channel[conf.channel_num].channel_flags = CHANNEL_F_BUFFERED |
						       CHANNEL_F_STREAM |
						       CHANNEL_F_ERRORS;
	conf.channel_num++;
};

tcp_line : T_TCP T_DEFAULT '{' tcp_options '}'
{
	if (conf.channel_type_global != CHANNEL_NONE &&
	    conf.channel_type_global != CHANNEL_TCP) {
		print_err(CTD_CFG_ERROR, "cannot use `TCP' with other "
					 "dedicated link protocols!");
		exit(EXIT_FAILURE);
	}
	conf.channel_type_global = CHANNEL_TCP;
	conf.channel[conf.channel_num].channel_type = CHANNEL_TCP;
	conf.channel[conf.channel_num].channel_flags = CHANNEL_F_DEFAULT |
						       CHANNEL_F_BUFFERED |
						       CHANNEL_F_STREAM |
						       CHANNEL_F_ERRORS;
	conf.channel_default = conf.channel_num;
	conf.channel_num++;
};

tcp_options :
	    | tcp_options tcp_option;

tcp_option : T_IPV4_ADDR T_IP
{
	__max_dedicated_links_reached();

	if (!inet_aton($2, &conf.channel[conf.channel_num].u.tcp.server.ipv4)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4 address", $2);
		break;
	}
	conf.channel[conf.channel_num].u.tcp.ipproto = AF_INET;
};

tcp_option : T_IPV6_ADDR T_IP
{
	__max_dedicated_links_reached();

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2,
		      &conf.channel[conf.channel_num].u.tcp.server.ipv6) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6 address", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
	break;
#endif
	conf.channel[conf.channel_num].u.tcp.ipproto = AF_INET6;
};

tcp_option : T_IPV4_DEST_ADDR T_IP
{
	__max_dedicated_links_reached();

	if (!inet_aton($2, &conf.channel[conf.channel_num].u.tcp.client)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4 address", $2);
		break;
	}
	conf.channel[conf.channel_num].u.tcp.ipproto = AF_INET;
};

tcp_option : T_IPV6_DEST_ADDR T_IP
{
	__max_dedicated_links_reached();

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2,
		      &conf.channel[conf.channel_num].u.tcp.client) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6 address", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
	break;
#endif
	conf.channel[conf.channel_num].u.tcp.ipproto = AF_INET6;
};

tcp_option : T_IFACE T_STRING
{
	int idx;

	__max_dedicated_links_reached();
	strncpy(conf.channel[conf.channel_num].channel_ifname, $2, IFNAMSIZ);

	idx = if_nametoindex($2);
	if (!idx) {
		print_err(CTD_CFG_WARN, "%s is an invalid interface", $2);
		break;
	}
	conf.channel[conf.channel_num].u.tcp.server.ipv6.scope_id = idx;
};

tcp_option : T_PORT T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.tcp.port = $2;
};

tcp_option: T_SNDBUFF T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.tcp.sndbuf = $2;
};

tcp_option: T_RCVBUFF T_NUMBER
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.tcp.rcvbuf = $2;
};

tcp_option: T_CHECKSUM T_ON 
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.tcp.checksum = 0;
};

tcp_option: T_CHECKSUM T_OFF
{
	__max_dedicated_links_reached();
	conf.channel[conf.channel_num].u.tcp.checksum = 1;
};

tcp_option: T_ERROR_QUEUE_LENGTH T_NUMBER
{
	__max_dedicated_links_reached();
	CONFIG(channelc).error_queue_length = $2;
};

hashsize : T_HASHSIZE T_NUMBER
{
	conf.hashsize = $2;
};

hashlimit: T_HASHLIMIT T_NUMBER
{
	conf.limit = $2;
};

unix_line: T_UNIX '{' unix_options '}';

unix_options:
	    | unix_options unix_option
	    ;

unix_option : T_PATH T_PATH_VAL
{
	strcpy(conf.local.path, $2);
};

unix_option : T_BACKLOG T_NUMBER
{
	conf.local.backlog = $2;
};

ignore_protocol: T_IGNORE_PROTOCOL '{' ignore_proto_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_L4PROTO,
			    CT_FILTER_NEGATIVE);

	print_err(CTD_CFG_WARN, "the clause `IgnoreProtocol' is "
				"obsolete. Use `Filter' instead");
};

ignore_proto_list:
		 | ignore_proto_list ignore_proto
		 ;

ignore_proto: T_NUMBER
{
	if ($1 < IPPROTO_MAX)
		ct_filter_add_proto(STATE(us_filter), $1);
	else
		print_err(CTD_CFG_WARN, "protocol number `%d' is freak", $1);
};

ignore_proto: T_STRING
{
	struct protoent *pent;

	pent = getprotobyname($1);
	if (pent == NULL) {
		print_err(CTD_CFG_WARN, "getprotobyname() cannot find "
					"protocol `%s' in /etc/protocols", $1);
		break;
	}
	ct_filter_add_proto(STATE(us_filter), pent->p_proto);
};

sync: T_SYNC '{' sync_list '}'
{
	if (conf.flags & CTD_CTNL) {
		print_err(CTD_CFG_ERROR, "cannot use both `Stats' and `Sync' "
					 "clauses in conntrackd.conf");
		exit(EXIT_FAILURE);
	}
	conf.flags |= CTD_SYNC_MODE | CTD_CTNL;
};

sync_list:
	 | sync_list sync_line;

sync_line: refreshtime
	 | expiretime
	 | timeout
	 | purge
	 | checksum
	 | multicast_line
	 | udp_line
	 | tcp_line
	 | relax_transitions
	 | delay_destroy_msgs
	 | sync_mode_alarm
	 | sync_mode_ftfw
	 | sync_mode_notrack
	 | listen_to
	 | state_replication
	 | cache_writethrough
	 | destroy_timeout
	 | option_line
	 ;

option_line: T_OPTIONS '{' options '}';

options:
       | options option 
       ;

option: T_TCP_WINDOW_TRACKING T_ON
{
	CONFIG(sync).tcp_window_tracking = 1;
};

option: T_TCP_WINDOW_TRACKING T_OFF
{
	CONFIG(sync).tcp_window_tracking = 0;
};

option: T_EXPECT_SYNC T_ON
{
	CONFIG(flags) |= CTD_EXPECT;
	CONFIG(netlink).subsys_id = NFNL_SUBSYS_NONE;
	CONFIG(netlink).groups = NF_NETLINK_CONNTRACK_NEW |
				 NF_NETLINK_CONNTRACK_UPDATE |
				 NF_NETLINK_CONNTRACK_DESTROY |
				 NF_NETLINK_CONNTRACK_EXP_NEW |
				 NF_NETLINK_CONNTRACK_EXP_UPDATE |
				 NF_NETLINK_CONNTRACK_EXP_DESTROY;
};

option: T_EXPECT_SYNC T_OFF
{
	CONFIG(netlink).subsys_id = NFNL_SUBSYS_CTNETLINK;
	CONFIG(netlink).groups = NF_NETLINK_CONNTRACK_NEW |
				 NF_NETLINK_CONNTRACK_UPDATE |
				 NF_NETLINK_CONNTRACK_DESTROY;
};

option: T_EXPECT_SYNC '{' expect_list '}'
{
	CONFIG(flags) |= CTD_EXPECT;
	CONFIG(netlink).subsys_id = NFNL_SUBSYS_NONE;
	CONFIG(netlink).groups = NF_NETLINK_CONNTRACK_NEW |
				 NF_NETLINK_CONNTRACK_UPDATE |
				 NF_NETLINK_CONNTRACK_DESTROY |
				 NF_NETLINK_CONNTRACK_EXP_NEW |
				 NF_NETLINK_CONNTRACK_EXP_UPDATE |
				 NF_NETLINK_CONNTRACK_EXP_DESTROY;
};

expect_list:
            | expect_list expect_item ;

expect_item: T_STRING
{
	exp_filter_add(STATE(exp_filter), $1);
}

sync_mode_alarm: T_SYNC_MODE T_ALARM '{' sync_mode_alarm_list '}'
{
	conf.flags |= CTD_SYNC_ALARM;
};

sync_mode_ftfw: T_SYNC_MODE T_FTFW '{' sync_mode_ftfw_list '}'
{
	conf.flags |= CTD_SYNC_FTFW;
};

sync_mode_notrack: T_SYNC_MODE T_NOTRACK '{' sync_mode_notrack_list '}'
{
	conf.flags |= CTD_SYNC_NOTRACK;
};

sync_mode_alarm_list:
	      | sync_mode_alarm_list sync_mode_alarm_line;

sync_mode_alarm_line: refreshtime
              		 | expiretime
	     		 | timeout
			 | purge
			 | relax_transitions
			 | delay_destroy_msgs
			 ;

sync_mode_ftfw_list:
	      | sync_mode_ftfw_list sync_mode_ftfw_line;

sync_mode_ftfw_line: resend_queue_size
		   | resend_buffer_size
		   | timeout
		   | purge
		   | window_size
		   | disable_external_cache
		   ;

sync_mode_notrack_list:
	      | sync_mode_notrack_list sync_mode_notrack_line;

sync_mode_notrack_line: timeout
		      | purge
		      | disable_internal_cache
		      | disable_external_cache
		      ;

disable_internal_cache: T_DISABLE_INTERNAL_CACHE T_ON
{
	conf.sync.internal_cache_disable = 1;
};

disable_internal_cache: T_DISABLE_INTERNAL_CACHE T_OFF
{
	conf.sync.internal_cache_disable = 0;
};

disable_external_cache: T_DISABLE_EXTERNAL_CACHE T_ON
{
	conf.sync.external_cache_disable = 1;
};

disable_external_cache: T_DISABLE_EXTERNAL_CACHE T_OFF
{
	conf.sync.external_cache_disable = 0;
};

resend_buffer_size: T_RESEND_BUFFER_SIZE T_NUMBER
{
	print_err(CTD_CFG_WARN, "`ResendBufferSize' is deprecated. "
				"Use `ResendQueueSize' instead");
};

resend_queue_size: T_RESEND_QUEUE_SIZE T_NUMBER
{
	conf.resend_queue_size = $2;
};

window_size: T_WINDOWSIZE T_NUMBER
{
	conf.window_size = $2;
};

destroy_timeout: T_DESTROY_TIMEOUT T_NUMBER
{
	print_err(CTD_CFG_WARN, "`DestroyTimeout' is deprecated. Remove it");
};

relax_transitions: T_RELAX_TRANSITIONS
{
	print_err(CTD_CFG_WARN, "`RelaxTransitions' clause is obsolete. "
				"Please, remove it from conntrackd.conf");
};

delay_destroy_msgs: T_DELAY
{
	print_err(CTD_CFG_WARN, "`DelayDestroyMessages' clause is obsolete. "
				"Please, remove it from conntrackd.conf");
};

listen_to: T_LISTEN_TO T_IP
{
	print_err(CTD_CFG_WARN, "the clause `ListenTo' is obsolete, ignoring");
};

state_replication: T_REPLICATE states T_FOR state_proto
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_STATE,
			    CT_FILTER_POSITIVE);

	print_err(CTD_CFG_WARN, "the clause `Replicate' is obsolete. "
				"Use `Filter' instead");
};

states:
      | states state;

state_proto: T_STRING
{
	if (strncmp($1, "TCP", strlen("TCP")) != 0) {
		print_err(CTD_CFG_WARN, "unsupported protocol `%s' in line %d",
					$1, yylineno);
	}
};
state: tcp_state;

tcp_states:
	  | tcp_states tcp_state;

tcp_state: T_SYN_SENT
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_SYN_SENT);

	__kernel_filter_add_state(TCP_CONNTRACK_SYN_SENT);
};
tcp_state: T_SYN_RECV
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_SYN_RECV);

	__kernel_filter_add_state(TCP_CONNTRACK_SYN_RECV);
};
tcp_state: T_ESTABLISHED
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_ESTABLISHED);

	__kernel_filter_add_state(TCP_CONNTRACK_ESTABLISHED);
};
tcp_state: T_FIN_WAIT
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_FIN_WAIT);

	__kernel_filter_add_state(TCP_CONNTRACK_FIN_WAIT);
};
tcp_state: T_CLOSE_WAIT
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_CLOSE_WAIT);

	__kernel_filter_add_state(TCP_CONNTRACK_CLOSE_WAIT);
};
tcp_state: T_LAST_ACK
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_LAST_ACK);

	__kernel_filter_add_state(TCP_CONNTRACK_LAST_ACK);
};
tcp_state: T_TIME_WAIT
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_TIME_WAIT);

	__kernel_filter_add_state(TCP_CONNTRACK_TIME_WAIT);
};
tcp_state: T_CLOSE
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_CLOSE);

	__kernel_filter_add_state(TCP_CONNTRACK_CLOSE);
};
tcp_state: T_LISTEN
{
	ct_filter_add_state(STATE(us_filter),
			    IPPROTO_TCP,
			    TCP_CONNTRACK_LISTEN);

	__kernel_filter_add_state(TCP_CONNTRACK_LISTEN);
};

cache_writethrough: T_WRITE_THROUGH T_ON
{
	print_err(CTD_CFG_WARN, "`CacheWriteThrough' clause is obsolete, "
				"ignoring");
};

cache_writethrough: T_WRITE_THROUGH T_OFF
{
	print_err(CTD_CFG_WARN, "`CacheWriteThrough' clause is obsolete, "
				"ignoring");
};

general: T_GENERAL '{' general_list '}';

general_list:
	    | general_list general_line
	    ;

general_line: hashsize
	    | hashlimit
	    | logfile_bool
	    | logfile_path
	    | syslog_facility
	    | syslog_bool
	    | lock
	    | unix_line
	    | netlink_buffer_size
	    | netlink_buffer_size_max_grown
	    | family
	    | event_iterations_limit
	    | poll_secs
	    | filter
	    | netlink_overrun_resync
	    | netlink_events_reliable
	    | nice
	    | scheduler
	    ;

netlink_buffer_size: T_BUFFER_SIZE T_NUMBER
{
	conf.netlink_buffer_size = $2;
};

netlink_buffer_size_max_grown : T_BUFFER_SIZE_MAX_GROWN T_NUMBER
{
	conf.netlink_buffer_size_max_grown = $2;
};

netlink_overrun_resync : T_NETLINK_OVERRUN_RESYNC T_ON
{
	conf.nl_overrun_resync = 30;
};

netlink_overrun_resync : T_NETLINK_OVERRUN_RESYNC T_OFF
{
	conf.nl_overrun_resync = -1;
};

netlink_overrun_resync : T_NETLINK_OVERRUN_RESYNC T_NUMBER
{
	conf.nl_overrun_resync = $2;
};

netlink_events_reliable : T_NETLINK_EVENTS_RELIABLE T_ON
{
	conf.netlink.events_reliable = 1;
};

netlink_events_reliable : T_NETLINK_EVENTS_RELIABLE T_OFF
{
	conf.netlink.events_reliable = 0;
};

nice : T_NICE T_SIGNED_NUMBER
{
	conf.nice = $2;
};

scheduler : T_SCHEDULER '{' scheduler_options '}';

scheduler_options :
		  | scheduler_options scheduler_line
		  ;

scheduler_line : T_TYPE T_STRING
{
	if (strcasecmp($2, "rr") == 0) {
		conf.sched.type = SCHED_RR;
	} else if (strcasecmp($2, "fifo") == 0) {
		conf.sched.type = SCHED_FIFO;
	} else {
		print_err(CTD_CFG_ERROR, "unknown scheduler `%s'", $2);
		exit(EXIT_FAILURE);
	}
};

scheduler_line : T_PRIO T_NUMBER
{
	conf.sched.prio = $2;
	if (conf.sched.prio < 0 || conf.sched.prio > 99) {
		print_err(CTD_CFG_ERROR, "`Priority' must be [0, 99]\n", $2);
		exit(EXIT_FAILURE);
	}
};

family : T_FAMILY T_STRING
{
	if (strncmp($2, "IPv6", strlen("IPv6")) == 0)
		conf.family = AF_INET6;
	else
		conf.family = AF_INET;
};

event_iterations_limit : T_EVENT_ITER_LIMIT T_NUMBER
{
	CONFIG(event_iterations_limit) = $2;
};

poll_secs: T_POLL_SECS T_NUMBER
{
	conf.flags |= CTD_POLL;
	conf.poll_kernel_secs = $2;
	if (conf.poll_kernel_secs == 0) {
		print_err(CTD_CFG_ERROR, "`PollSecs' clause must be > 0");
		exit(EXIT_FAILURE);
	}
};

filter : T_FILTER '{' filter_list '}'
{
	CONFIG(filter_from_kernelspace) = 0;
};

filter : T_FILTER T_FROM T_USERSPACE '{' filter_list '}'
{
	CONFIG(filter_from_kernelspace) = 0;
};

filter : T_FILTER T_FROM T_KERNELSPACE '{' filter_list '}'
{
	CONFIG(filter_from_kernelspace) = 1;
};

filter_list : 
	    | filter_list filter_item;

filter_item : T_PROTOCOL T_ACCEPT '{' filter_protocol_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_L4PROTO,
			    CT_FILTER_POSITIVE);

	__kernel_filter_start();
};

filter_item : T_PROTOCOL T_IGNORE '{' filter_protocol_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_L4PROTO,
			    CT_FILTER_NEGATIVE);

	__kernel_filter_start();

	nfct_filter_set_logic(STATE(filter),
			      NFCT_FILTER_L4PROTO,
			      NFCT_FILTER_LOGIC_NEGATIVE);
};

filter_protocol_list :
		     | filter_protocol_list filter_protocol_item;

filter_protocol_item : T_STRING
{
	struct protoent *pent;

	pent = getprotobyname($1);
	if (pent == NULL) {
		print_err(CTD_CFG_WARN, "getprotobyname() cannot find "
					"protocol `%s' in /etc/protocols", $1);
		break;
	}
	ct_filter_add_proto(STATE(us_filter), pent->p_proto);

	__kernel_filter_start();

	nfct_filter_add_attr_u32(STATE(filter),
				 NFCT_FILTER_L4PROTO,
				 pent->p_proto);
};

filter_protocol_item : T_TCP
{
	struct protoent *pent;

	pent = getprotobyname("tcp");
	if (pent == NULL) {
		print_err(CTD_CFG_WARN, "getprotobyname() cannot find "
					"protocol `tcp' in /etc/protocols");
		break;
	}
	ct_filter_add_proto(STATE(us_filter), pent->p_proto);

	__kernel_filter_start();

	nfct_filter_add_attr_u32(STATE(filter),
				 NFCT_FILTER_L4PROTO,
				 pent->p_proto);
};

filter_protocol_item : T_UDP
{
	struct protoent *pent;

	pent = getprotobyname("udp");
	if (pent == NULL) {
		print_err(CTD_CFG_WARN, "getprotobyname() cannot find "
					"protocol `udp' in /etc/protocols");
		break;
	}
	ct_filter_add_proto(STATE(us_filter), pent->p_proto);

	__kernel_filter_start();

	nfct_filter_add_attr_u32(STATE(filter),
				 NFCT_FILTER_L4PROTO,
				 pent->p_proto);
};

filter_item : T_ADDRESS T_ACCEPT '{' filter_address_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_ADDRESS,
			    CT_FILTER_POSITIVE);

	__kernel_filter_start();
};

filter_item : T_ADDRESS T_IGNORE '{' filter_address_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_ADDRESS,
			    CT_FILTER_NEGATIVE);

	__kernel_filter_start();

	nfct_filter_set_logic(STATE(filter),
			      NFCT_FILTER_SRC_IPV4,
			      NFCT_FILTER_LOGIC_NEGATIVE);
	nfct_filter_set_logic(STATE(filter),
			      NFCT_FILTER_DST_IPV4,
			      NFCT_FILTER_LOGIC_NEGATIVE);
	nfct_filter_set_logic(STATE(filter),
			      NFCT_FILTER_SRC_IPV6,
			      NFCT_FILTER_LOGIC_NEGATIVE);
	nfct_filter_set_logic(STATE(filter),
			      NFCT_FILTER_DST_IPV6,
			      NFCT_FILTER_LOGIC_NEGATIVE);
};

filter_address_list :
		    | filter_address_list filter_address_item;

filter_address_item : T_IPV4_ADDR T_IP
{
	union inet_address ip;
	char *slash;
	unsigned int cidr = 32;

	memset(&ip, 0, sizeof(union inet_address));

	slash = strchr($2, '/');
	if (slash) {
		*slash = '\0';
		cidr = atoi(slash+1);
		if (cidr > 32) {
			print_err(CTD_CFG_WARN, "%s/%d is not a valid network, "
						"ignoring", $2, cidr);
			break;
		}
	}

	if (!inet_aton($2, &ip.ipv4)) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv4, ignoring", $2);
		break;
	}

	if (slash && cidr < 32) {
		/* network byte order */
		struct ct_filter_netmask_ipv4 tmp = {
			.ip = ip.ipv4,
			.mask = ipv4_cidr2mask_net(cidr)
		};

		if (!ct_filter_add_netmask(STATE(us_filter), &tmp, AF_INET)) {
			if (errno == EEXIST)
				print_err(CTD_CFG_WARN, "netmask %s is "
							"repeated in the "
							"ignore pool", $2);
		}
	} else {
		if (!ct_filter_add_ip(STATE(us_filter), &ip, AF_INET)) {
			if (errno == EEXIST)
				print_err(CTD_CFG_WARN, "IP %s is repeated in "
							"the ignore pool", $2);
			if (errno == ENOSPC)
				print_err(CTD_CFG_WARN, "too many IP in the "
							"ignore pool!");
		}
	}
	__kernel_filter_start();

	/* host byte order */
	struct nfct_filter_ipv4 filter_ipv4 = {
		.addr = ntohl(ip.ipv4),
		.mask = ipv4_cidr2mask_host(cidr),
	};

	nfct_filter_add_attr(STATE(filter), NFCT_FILTER_SRC_IPV4, &filter_ipv4);
	nfct_filter_add_attr(STATE(filter), NFCT_FILTER_DST_IPV4, &filter_ipv4);
};

filter_address_item : T_IPV6_ADDR T_IP
{
	union inet_address ip;
	char *slash;
	int cidr = 128;
	struct nfct_filter_ipv6 filter_ipv6;

	memset(&ip, 0, sizeof(union inet_address));

	slash = strchr($2, '/');
	if (slash) {
		*slash = '\0';
		cidr = atoi(slash+1);
		if (cidr > 128) {
			print_err(CTD_CFG_WARN, "%s/%d is not a valid network, "
						"ignoring", $2, cidr);
			break;
		}
	}

#ifdef HAVE_INET_PTON_IPV6
	if (inet_pton(AF_INET6, $2, &ip.ipv6) <= 0) {
		print_err(CTD_CFG_WARN, "%s is not a valid IPv6, ignoring", $2);
		break;
	}
#else
	print_err(CTD_CFG_WARN, "cannot find inet_pton(), IPv6 unsupported!");
	break;
#endif
	if (slash && cidr < 128) {
		struct ct_filter_netmask_ipv6 tmp;

		memcpy(tmp.ip, ip.ipv6, sizeof(uint32_t)*4);
		ipv6_cidr2mask_net(cidr, tmp.mask);
		if (!ct_filter_add_netmask(STATE(us_filter), &tmp, AF_INET6)) {
			if (errno == EEXIST)
				print_err(CTD_CFG_WARN, "netmask %s is "
							"repeated in the "
							"ignore pool", $2);
		}
	} else {
		if (!ct_filter_add_ip(STATE(us_filter), &ip, AF_INET6)) {
			if (errno == EEXIST)
				print_err(CTD_CFG_WARN, "IP %s is repeated in "
							"the ignore pool", $2);
			if (errno == ENOSPC)
				print_err(CTD_CFG_WARN, "too many IP in the "
							"ignore pool!");
		}
	}
	__kernel_filter_start();

	/* host byte order */
	ipv6_addr2addr_host(ip.ipv6, filter_ipv6.addr);
	ipv6_cidr2mask_host(cidr, filter_ipv6.mask);

	nfct_filter_add_attr(STATE(filter), NFCT_FILTER_SRC_IPV6, &filter_ipv6);
	nfct_filter_add_attr(STATE(filter), NFCT_FILTER_DST_IPV6, &filter_ipv6);
};

filter_item : T_STATE T_ACCEPT '{' filter_state_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_STATE,
			    CT_FILTER_POSITIVE);

	__kernel_filter_start();
};

filter_item : T_STATE T_IGNORE '{' filter_state_list '}'
{
	ct_filter_set_logic(STATE(us_filter),
			    CT_FILTER_STATE,
			    CT_FILTER_NEGATIVE);


	__kernel_filter_start();

	nfct_filter_set_logic(STATE(filter),
			      NFCT_FILTER_L4PROTO_STATE,
			      NFCT_FILTER_LOGIC_NEGATIVE);
};

filter_state_list :
		  | filter_state_list filter_state_item;

filter_state_item : tcp_states T_FOR T_TCP;

stats: T_STATS '{' stats_list '}'
{
	if (conf.flags & CTD_CTNL) {
		print_err(CTD_CFG_ERROR, "cannot use both `Stats' and `Sync' "
					 "clauses in conntrackd.conf");
		exit(EXIT_FAILURE);
	}
	conf.flags |= CTD_STATS_MODE | CTD_CTNL;
};

stats_list:
	 | stats_list stat_line
	 ;

stat_line: stat_logfile_bool
	 | stat_logfile_path
	 | stat_syslog_bool
	 | stat_syslog_facility
	 | buffer_size
	 ;

stat_logfile_bool : T_LOG T_ON
{
	strncpy(conf.stats.logfile, DEFAULT_STATS_LOGFILE, FILENAME_MAXLEN);
};

stat_logfile_bool : T_LOG T_OFF
{
};

stat_logfile_path : T_LOG T_PATH_VAL
{
	strncpy(conf.stats.logfile, $2, FILENAME_MAXLEN);
};

stat_syslog_bool : T_SYSLOG T_ON
{
	conf.stats.syslog_facility = DEFAULT_SYSLOG_FACILITY;
};

stat_syslog_bool : T_SYSLOG T_OFF
{
	conf.stats.syslog_facility = -1;
}

stat_syslog_facility : T_SYSLOG T_STRING
{
	if (!strcmp($2, "daemon"))
		conf.stats.syslog_facility = LOG_DAEMON;
	else if (!strcmp($2, "local0"))
		conf.stats.syslog_facility = LOG_LOCAL0;
	else if (!strcmp($2, "local1"))
		conf.stats.syslog_facility = LOG_LOCAL1;
	else if (!strcmp($2, "local2"))
		conf.stats.syslog_facility = LOG_LOCAL2;
	else if (!strcmp($2, "local3"))
		conf.stats.syslog_facility = LOG_LOCAL3;
	else if (!strcmp($2, "local4"))
		conf.stats.syslog_facility = LOG_LOCAL4;
	else if (!strcmp($2, "local5"))
		conf.stats.syslog_facility = LOG_LOCAL5;
	else if (!strcmp($2, "local6"))
		conf.stats.syslog_facility = LOG_LOCAL6;
	else if (!strcmp($2, "local7"))
		conf.stats.syslog_facility = LOG_LOCAL7;
	else {
		print_err(CTD_CFG_WARN, "'%s' is not a known syslog facility, "
					"ignoring.", $2);
		break;
	}

	if (conf.syslog_facility != -1 &&
	    conf.stats.syslog_facility != conf.syslog_facility)
		print_err(CTD_CFG_WARN, "conflicting Syslog facility "
					"values, defaulting to General");
};

buffer_size: T_STAT_BUFFER_SIZE T_NUMBER
{
	print_err(CTD_CFG_WARN, "`LogFileBufferSize' is deprecated");
};

helper: T_HELPER '{' helper_list '}'
{
	conf.flags |= CTD_HELPER;
};

helper_list:
	    | helper_list helper_line
	    ;

helper_line: helper_type
	    ;

helper_type: T_TYPE T_STRING T_STRING T_STRING '{' helper_type_list  '}'
{
	struct ctd_helper_instance *helper_inst;
	struct ctd_helper *helper;
	struct stack_item *e;
	uint16_t l3proto;
	uint8_t l4proto;

	if (strcmp($3, "inet") == 0)
		l3proto = AF_INET;
	else if (strcmp($3, "inet6") == 0)
		l3proto = AF_INET6;
	else {
		print_err(CTD_CFG_ERROR, "unknown layer 3 protocol");
		exit(EXIT_FAILURE);
	}

	if (strcmp($4, "tcp") == 0)
		l4proto = IPPROTO_TCP;
	else if (strcmp($4, "udp") == 0)
		l4proto = IPPROTO_UDP;
	else {
		print_err(CTD_CFG_ERROR, "unknown layer 4 protocol");
		exit(EXIT_FAILURE);
	}

	/* XXX use configure.ac definitions. */
	helper = helper_find("/usr/lib/conntrack-tools", $2, l4proto, RTLD_NOW);
	if (helper == NULL) {
		print_err(CTD_CFG_ERROR, "Unknown `%s' helper", $2);
		exit(EXIT_FAILURE);
	}

	helper_inst = calloc(1, sizeof(struct ctd_helper_instance));
	if (helper_inst == NULL)
		break;

	helper_inst->l3proto = l3proto;
	helper_inst->l4proto = l4proto;
	helper_inst->helper = helper;

	while ((e = stack_item_pop(&symbol_stack, -1)) != NULL) {

		switch(e->type) {
		case SYMBOL_HELPER_QUEUE_NUM: {
			int *qnum = (int *) &e->data;

			helper_inst->queue_num = *qnum;
			stack_item_free(e);
			break;
		}
		case SYMBOL_HELPER_QUEUE_LEN: {
			int *qlen = (int *) &e->data;

			helper_inst->queue_len = *qlen;
			stack_item_free(e);
			break;
		}
		case SYMBOL_HELPER_POLICY_EXPECT_ROOT: {
			struct ctd_helper_policy *pol =
				(struct ctd_helper_policy *) &e->data;
			struct ctd_helper_policy *matching = NULL;
			int i;

			for (i=0; i<CTD_HELPER_POLICY_MAX; i++) {
				if (strcmp(helper->policy[i].name,
					   pol->name) != 0)
					continue;

				matching = pol;
				break;
			}
			if (matching == NULL) {
				print_err(CTD_CFG_ERROR,
					  "Unknown policy `%s' in helper "
					  "configuration", pol->name);
				exit(EXIT_FAILURE);
			}
			/* FIXME: First set default policy, then change only
			 * tuned fields, not everything.
			 */
			memcpy(&helper->policy[i], pol,
				sizeof(struct ctd_helper_policy));

			stack_item_free(e);
			break;
		}
		default:
			print_err(CTD_CFG_ERROR,
				  "Unexpected symbol parsing helper policy");
				exit(EXIT_FAILURE);
			break;
		}
	}
	list_add(&helper_inst->head, &CONFIG(cthelper).list);
};

helper_type_list:
		| helper_type_list helper_type_line
		;

helper_type_line: helper_type
		;

helper_type: T_HELPER_QUEUE_NUM T_NUMBER
{
	int *qnum;
	struct stack_item *e;

	e = stack_item_alloc(SYMBOL_HELPER_QUEUE_NUM, sizeof(int));
	qnum = (int *) e->data;
	*qnum = $2;
	stack_item_push(&symbol_stack, e);
};

helper_type: T_HELPER_QUEUE_LEN T_NUMBER
{
	int *qlen;
	struct stack_item *e;

	e = stack_item_alloc(SYMBOL_HELPER_QUEUE_LEN, sizeof(int));
	qlen = (int *) e->data;
	*qlen = $2;
	stack_item_push(&symbol_stack, e);
};

helper_type: T_HELPER_POLICY T_STRING '{' helper_policy_list '}'
{
	struct stack_item *e;
	struct ctd_helper_policy *policy;

	e = stack_item_pop(&symbol_stack, SYMBOL_HELPER_EXPECT_POLICY_LEAF);
	if (e == NULL) {
		print_err(CTD_CFG_ERROR,
			  "Helper policy configuration empty, fix your "
			  "configuration file, please");
		exit(EXIT_FAILURE);
		break;
	}

	policy = (struct ctd_helper_policy *) &e->data;
	strncpy(policy->name, $2, CTD_HELPER_NAME_LEN);
	policy->name[CTD_HELPER_NAME_LEN-1] = '\0';
	/* Now object is complete. */
	e->type = SYMBOL_HELPER_POLICY_EXPECT_ROOT;
	stack_item_push(&symbol_stack, e);
};

helper_policy_list:
		  | helper_policy_list helper_policy_line
		  ;

helper_policy_line: helper_policy_expect_max
		  | helper_policy_expect_timeout
		  ;

helper_policy_expect_max: T_HELPER_EXPECT_MAX T_NUMBER
{
	struct stack_item *e;
	struct ctd_helper_policy *policy;

	e = stack_item_pop(&symbol_stack, SYMBOL_HELPER_EXPECT_POLICY_LEAF);
	if (e == NULL) {
		e = stack_item_alloc(SYMBOL_HELPER_EXPECT_POLICY_LEAF,
				     sizeof(struct ctd_helper_policy));
	}
	policy = (struct ctd_helper_policy *) &e->data;
	policy->expect_max = $2;
	stack_item_push(&symbol_stack, e);
};

helper_policy_expect_timeout: T_HELPER_EXPECT_TIMEOUT T_NUMBER
{
	struct stack_item *e;
	struct ctd_helper_policy *policy;

	e = stack_item_pop(&symbol_stack, SYMBOL_HELPER_EXPECT_POLICY_LEAF);
	if (e == NULL) {
		e = stack_item_alloc(SYMBOL_HELPER_EXPECT_POLICY_LEAF,
				     sizeof(struct ctd_helper_policy));
	}
	policy = (struct ctd_helper_policy *) &e->data;
	policy->expect_timeout = $2;
	stack_item_push(&symbol_stack, e);
};

%%

int __attribute__((noreturn))
yyerror(char *msg)
{
	print_err(CTD_CFG_ERROR, "parsing config file in "
				 "line (%d), symbol '%s': %s",
				 yylineno, yytext, msg);
	exit(EXIT_FAILURE);
}

static void print_err(int type, const char *msg, ...)
{
	va_list args;

	va_start(args, msg);
	switch(type) {
	case CTD_CFG_ERROR:
		fprintf(stderr, "ERROR: ");
		break;
	case CTD_CFG_WARN:
		fprintf(stderr, "WARNING: ");
		break;
	default:
		fprintf(stderr, "?: ");
	}
	vfprintf(stderr, msg, args);
	va_end(args);
	fprintf(stderr,"\n");
}

static void __kernel_filter_start(void)
{
	if (!STATE(filter)) {
		STATE(filter) = nfct_filter_create();
		if (!STATE(filter)) {
			print_err(CTD_CFG_ERROR, "cannot create ignore pool!");
			exit(EXIT_FAILURE);
		}
	}
}

static void __kernel_filter_add_state(int value)
{
	__kernel_filter_start();

	struct nfct_filter_proto filter_proto = {
		.proto = IPPROTO_TCP,
		.state = value
	};
	nfct_filter_add_attr(STATE(filter),
			     NFCT_FILTER_L4PROTO_STATE,
			     &filter_proto);
}

static void __max_dedicated_links_reached(void)
{
	if (conf.channel_num >= MULTICHANNEL_MAX) {
		print_err(CTD_CFG_ERROR, "too many dedicated links in "
					 "the configuration file "
					 "(Maximum: %d)", MULTICHANNEL_MAX);
		exit(EXIT_FAILURE);
	}
}

int
init_config(char *filename)
{
	FILE *fp;

	fp = fopen(filename, "r");
	if (!fp)
		return -1;

	/* Zero may be a valid facility */
	CONFIG(syslog_facility) = -1;
	CONFIG(stats).syslog_facility = -1;
	CONFIG(netlink).subsys_id = -1;

	/* Initialize list of user-space helpers */
	INIT_LIST_HEAD(&CONFIG(cthelper).list);

	stack_init(&symbol_stack);

	yyrestart(fp);
	yyparse();
	fclose(fp);

	/* default to IPv4 */
	if (CONFIG(family) == 0)
		CONFIG(family) = AF_INET;

	/* set to default is not specified */
	if (strcmp(CONFIG(lockfile), "") == 0)
		strncpy(CONFIG(lockfile), DEFAULT_LOCKFILE, FILENAME_MAXLEN);

	/* default to 180 seconds of expiration time: cache entries */
	if (CONFIG(cache_timeout) == 0)
		CONFIG(cache_timeout) = 180;

	/* default to 60 seconds: purge kernel entries */
	if (CONFIG(purge_timeout) == 0)
		CONFIG(purge_timeout) = 60;

	/* default to 60 seconds of refresh time */
	if (CONFIG(refresh) == 0)
		CONFIG(refresh) = 60;

	if (CONFIG(resend_queue_size) == 0)
		CONFIG(resend_queue_size) = 131072;

	/* default to a window size of 300 packets */
	if (CONFIG(window_size) == 0)
		CONFIG(window_size) = 300;

	if (CONFIG(event_iterations_limit) == 0)
		CONFIG(event_iterations_limit) = 100;

	/* default number of bucket of the hashtable that are committed in
	   one run loop. XXX: no option available to tune this value yet. */
	if (CONFIG(general).commit_steps == 0)
		CONFIG(general).commit_steps = 8192;

	/* if overrun, automatically resync with kernel after 30 seconds */
	if (CONFIG(nl_overrun_resync) == 0)
		CONFIG(nl_overrun_resync) = 30;

	/* default to 128 elements in the channel error queue */
	if (CONFIG(channelc).error_queue_length == 0)
		CONFIG(channelc).error_queue_length = 128;

	if (CONFIG(netlink).subsys_id == -1) {
		CONFIG(netlink).subsys_id = NFNL_SUBSYS_CTNETLINK;
		CONFIG(netlink).groups = NF_NETLINK_CONNTRACK_NEW |
					 NF_NETLINK_CONNTRACK_UPDATE |
					 NF_NETLINK_CONNTRACK_DESTROY;
	}

	return 0;
}
