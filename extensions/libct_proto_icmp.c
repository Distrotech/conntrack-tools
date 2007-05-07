/*
 * (C) 2005-2007 by Pablo Neira Ayuso <pablo@netfilter.org>
 *     2005 by Harald Welte <laforge@netfilter.org>
 *
 *      This program is free software; you can redistribute it and/or modify
 *      it under the terms of the GNU General Public License as published by
 *      the Free Software Foundation; either version 2 of the License, or
 *      (at your option) any later version.
 *
 */
#include <stdio.h>
#include <getopt.h>
#include <stdlib.h>
#include <netinet/in.h> /* For htons */
#include <netinet/ip_icmp.h>
#include <libnetfilter_conntrack/libnetfilter_conntrack.h>
#include <libnetfilter_conntrack/libnetfilter_conntrack_icmp.h>
#include "conntrack.h"

static struct option opts[] = {
	{"icmp-type", 1, 0, '1'},
	{"icmp-code", 1, 0, '2'},
	{"icmp-id", 1, 0, '3'},
	{0, 0, 0, 0}
};

static void help()
{
	fprintf(stdout, "  --icmp-type\t\t\ticmp type\n");
	fprintf(stdout, "  --icmp-code\t\t\ticmp code\n");
	fprintf(stdout, "  --icmp-id\t\t\ticmp id\n");
}

static int parse(char c, char *argv[], 
		 struct nf_conntrack *ct,
		 struct nf_conntrack *exptuple,
		 struct nf_conntrack *mask,
		 unsigned int *flags)
{
	switch(c) {
		case '1':
			if (!optarg)
				break;

			nfct_set_attr_u8(ct, 
					 ATTR_ICMP_TYPE,
					 atoi(optarg));
			*flags |= ICMP_TYPE;
			break;
		case '2':
			if (!optarg)
				break;

			nfct_set_attr_u8(ct, 
					 ATTR_ICMP_CODE,
					 atoi(optarg));
			*flags |= ICMP_CODE;
			break;
		case '3':
			if (!optarg)
				break;

			nfct_set_attr_u16(ct,
					  ATTR_ICMP_ID,
					  htons(atoi(optarg)));
			*flags |= ICMP_ID;
			break;
	}
	return 1;
}

static int final_check(unsigned int flags,
		       unsigned int command,
		       struct nf_conntrack *ct)
{
	if (!(flags & ICMP_TYPE))
		return 0;
	else if (!(flags & ICMP_CODE))
		return 0;

	return 1;
}

static struct ctproto_handler icmp = {
	.name 		= "icmp",
	.protonum	= IPPROTO_ICMP,
	.parse_opts	= parse,
	.final_check	= final_check,
	.help		= help,
	.opts		= opts,
	.version	= VERSION,
};

static void __attribute__ ((constructor)) init(void);

static void init(void)
{
	register_proto(&icmp);
}
