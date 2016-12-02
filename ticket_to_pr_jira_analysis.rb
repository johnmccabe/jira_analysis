#!/usr/bin/env ruby
require 'net/http'
require 'json'
require 'yaml'
require 'net/https'
require 'uri'
require 'logger'
require 'set'
require 'ruby-progressbar'
require 'fileutils'

$LOG = Logger.new('ticket_to_pr_jira_analysis.log')
$LOG.level = Logger::INFO

OUTPUT_DIR = './output'
NOW = Time.now.strftime('%Y%m%d.%H%M%S')

# def log_info(message)
#   $LOG.info(message)
# end

unless File.directory?(OUTPUT_DIR)
  $LOG.info("Creating Output Directory #{OUTPUT_DIR}")
  FileUtils.mkdir_p(OUTPUT_DIR)
end

CONFIG_PATH = ENV['CONFIG_PATH'] || './config.yml'
config = YAML.load_file(CONFIG_PATH)

$jira_rest_endpoint = config['jira']['rest_endpoint']
$username = config['jira']['username']
$password = config['jira']['password']

def get_json_response(uri, ssl = true, retries = 5, timeout = 60000)
  response = {}
  begin
    $LOG.info("Making Request: #{uri}")
    http = Net::HTTP.new(uri.host, uri.port)
    # http.open_timeout = timeout
    # http.read_timeout = timeout
    if ssl
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
    request = Net::HTTP::Get.new(uri.request_uri)
    request.basic_auth($username, $password)
    response = http.request(request)
    return JSON.parse(response.body)
  rescue StandardError, Timeout::Error => e
    $LOG.info("Error making HTTP Request: retry = #{retries}, exception = #{e.message}")
    sleep rand(3..6)
    retry if (retries -= 1) > 0
  end
end

def search(jql)
  uri = URI.parse('%s/rest/api/2/search?jql=%s' % [$jira_rest_endpoint, jql])
  get_json_response(uri)
end

def get_issues_in_epic(epic_key)
  issues = []
  start_at = 0
  max_results = 50
  search_fields = %w(id key summary status)
  jql = "%22Epic%20Link%22=#{epic_key}&fields=#{search_fields.join(',')}&startAt=#{start_at}&maxResults=#{max_results}"
  result = search(jql)
  $LOG.info("Queried #{start_at}-#{start_at + max_results} out of #{result['total']} issues")
  issues.concat(result['issues'])
  while more_issues?(result)
    start_at += max_results
    jql = "%22Epic%20Link%22=#{epic_key}&fields=#{search_fields.join(',')}&startAt=#{start_at}&maxResults=#{max_results}"
    result = search(jql)
    issues.concat(result['issues'])
  end
  $LOG.info("Queried #{issues.size} issues")
  issues
end

def more_issues?(result)
  start_at = result['startAt']
  max_results = result['maxResults']
  total = result['total']
  $LOG.info('Checking if more results: startAt = %s, maxResults = %s, total = %s' % [start_at, max_results, total])
  start_at + max_results <= total + 1
end

# returns [errors, details]
def get_pr_details_from_issue(issue)
  $LOG.info("Getting PRs attached to #{issue['key']} (id: #{issue['id']} if present")
  uri = URI.parse('%s/rest/dev-status/1.0/issue/detail?issueId=%s&applicationType=github&dataType=pullrequest' % [$jira_rest_endpoint, issue['id']])
  response_json = get_json_response(uri)
  errors = response_json['errors']  # Array
  details = response_json['detail'] # Array
  $LOG.info("Found #{errors.size} errors and #{details.size} details")
  return [errors, details]
end

# returns an Set of repo names (string) from the details object obtained from a jira issue
def get_repos_from_details(details)
  repos = []
  details.each do |detail|
    prs = detail['pullRequests']    # Array
    $LOG.info("Found #{prs.size} pull requests")
    prs.each do |pr|
      pr_url = pr['url']
      extract_github_pr_regex = %r{\S+github\.com\/([\w-]+)\/([\w-]+)\/pull\/([^\/]+)}
      user, repository, pr_id = pr_url.match(extract_github_pr_regex).captures
      $LOG.info('Found pull request with, user: %s, repository: %s, pr_id: %s' % [user, repository, pr_id])
      repos << repository
    end
  end
  repos
end

def get_repo_distribition_in_epic(epic_key)
  repo_hash = {}
  issues = get_issues_in_epic(epic_key)
  progressbar = ProgressBar.create( :format => '%a %B %p%% %t',
                                    :total  => issues.size)
  issues.each do |issue|
    issue_key = issue['key']
    errors, details = get_pr_details_from_issue(issue)
    repos = get_repos_from_details(details)
    if repo_hash.key?(issue_key) then
      repo_hash[issue_key] = repo_hash[issue_key] | repos
    else
      repo_hash[issue_key] = repos
    end
    progressbar.increment
  end
  puts "FINISHED"
  puts "repo_hash keys = #{repo_hash.keys.size}"
  File.write("#{OUTPUT_DIR}/tickets_to_repos_#{NOW}.yml", repo_hash.to_yaml)
  File.write("#{OUTPUT_DIR}/tickets_to_repo_count_#{NOW}.yml", tickets_to_repo_count(repo_hash).to_yaml)
  File.write("#{OUTPUT_DIR}/repos_to_ticket_count_#{NOW}.yml", repos_to_ticket_count(repo_hash).to_yaml)
end


def tickets_to_repo_count(repo_hash)
  # returns a hash of tickets to count of repos for that ticket
  repo_hash.each_with_object({}) {|(k,v),o| o[k.to_sym]=v.size }
end

def repos_to_ticket_count(repo_hash)
  # can't just update the memo as Arrays are immutable and this only works on mutable objects
  # uniq_repos = repo_hash.values.each_with_object([]) {|repos, memo| repos.each {|repo| memo << repo}}.uniq
  repos_to_ticket_count = Hash.new(0)
  repo_hash.each do |ticket, repos|
    if repos.empty? then
      repos_to_ticket_count['none'] += 1
    else
      repos.uniq.each do |repo|
        repos_to_ticket_count[repo] += 1
      end
    end
  end
  repos_to_ticket_count
end

if $PROGRAM_NAME == __FILE__
  get_repo_distribition_in_epic(config['jira']['epic'])
end
