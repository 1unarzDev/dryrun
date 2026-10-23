export function developmentListenHost(value=process.env.DRYRUN_LISTEN_HOST??'127.0.0.1'){
 if(!['127.0.0.1','::1','0.0.0.0'].includes(value))throw new Error('invalid_development_listen_host');
 if(process.env.NODE_ENV==='production')throw new Error('production_authorization_provider_required');
 return value;
}
