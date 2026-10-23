// '::' listens on IPv6 and IPv4 together (Node dual-stack). A wired iPhone resolves <mac>.local to the Mac's IPv6
// link-local address on the USB link, which an IPv4-only 0.0.0.0 listener refuses (NSURLError -1004).
export function developmentListenHost(value=process.env.DRYRUN_LISTEN_HOST??'127.0.0.1'){
 if(!['127.0.0.1','::1','0.0.0.0','::'].includes(value))throw new Error('invalid_development_listen_host');
 if(process.env.NODE_ENV==='production')throw new Error('production_authorization_provider_required');
 return value;
}
