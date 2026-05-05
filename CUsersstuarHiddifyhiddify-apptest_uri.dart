void main() {
  final raw = 'rayn://h5vJxKi9eQJrubO67mOhP0v_cmyIqx1hhT_wtzqOuvus6OGbMtdELuYO01N7xaSfAWr5x83fWURwcdWwpC76t4ss02DlYmy8Lp9XPPX40XRXB8q8abf1QHZfP0RkebVsDGtQchP9YIgvDngAfyO6MM93eSpFk6Cv0R_tqyefNV86Qm8WwVJS6OkCGajm4YRi6t6KLzgasism4raJAxpCrNR-oH7tohq4ywqylSax9wvKF5tNQdjwwv2VkN_HXqKJi_hZ7UM3T7eYqcofFnDtPnUJMd_y8uAAawyIXXCQB_9JJcIFDBu-CzTZRdURBH_a4X6GfFzvVSW0oa60DPct7y-JbyQeYJh99xWtI2kZWpBQJbgKg2OGOhYgx-ZoKIK2liIWItiF8ADyRfmiVfzV3QLd8h-NPOAI2b7NzWySnzQpPNWSyRhbxQcEi-lNGTGxDMgudmN_lUj3Rrjdjqez3-z_hktXooL2NZfhIzDSffMDX3lX0hawIVfwRPpkInXbwigtFBGaYUPxbvzksTolc2TaZOBmPEVzm4rmajIeHgXHjurguZ_Oc_byjfkHLwcLk5cc0vgpg7OXeG-4vjFEaC8TMv1CDEWwD9Q7sprb9PZUaoZcg4jG4IvJGrFtUZu8oIDMKwDAmixi5t2uTGpkiMqnk11Cl4uy3tT62kBRHWI';
  final uri = Uri.parse(raw);
  print('scheme: ${uri.scheme}');
  print('hasAuthority: ${uri.hasAuthority}');
  print('host: ${uri.host}');
  print('path: ${uri.path}');
  print('toString: ${uri.toString()}');
  print('host == raw token? ${uri.host == raw.substring(7)}');
}
