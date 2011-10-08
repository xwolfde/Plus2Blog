#!/usr/bin/perl

use strict;
use LWP::UserAgent;
use JSON;
use Storable;
use XMLRPC::Lite;
###############################################################################
my $CONFIG = {
        "api_key"               => 'your-api-key',
		# API-Key for this script;
		# Get yourself an api-key at http://developers.google.com/+/api/oauth#apikey
	"userid"		=> 'your-user-id',
		# Google userid, from which you want to get the stream
	"url_blogxmlrpc"	=> 'https://your-blog-url/xmlrpc.php',
		# URL to the XML RPC Api of the blog
	"blog_username"		=> 'your-blog-username',
	"blog_password"		=> 'your-blog-password',
	"blog_id"		=> 1,
		# Blog-Id, mostly this is 1 if you dont use a multiuser-blogging-system
	"blog_defaultcategory"	=> "MyGooglePlusStream",
		# Default category of entries 
	"url_googleapi"		=> 'https://www.googleapis.com/',
	"uri_activitylist"	=> '/plus/v1/people/',
	"fieldfilter"		=> "&fields=items(object(actor%2Cattachments%2Ccontent%2Cid%2CobjectType%2CoriginalContent%2Creplies%2Curl)%2Cpublished%2Ctitle%2Curl%2Cverb)",
		# For blogposts we only need a small set of data-fields
	"onlyposts"		=> 1,
		 # Set to 0, if also reshares
	"show_attachments"	=> 1,
		# Add Attachment as part of the article
	"cssclass_attachments"	=> "attachment clearfix",
		# CSS class for all attachments
	"article_minlength"	=> 200,
		# Minimum number of chars a g+ article should have if it
		# gets posted as blogarticle
	"cssclass_articleborder" => "",
		# if a div with a class should sorround the text, enter a classname here
	"add_paragraph"		=> 1,
		# if a paragraph-tag shpuld be placed around the textcontent, set this to 1
	"show_attachment_linkcontent"	=> 1,
		# if attachments will also display the generated infotext about the target, set this to 1
	"cssclass_linkcontent"	=> "linkinfo",	
		# if generated infotext should be encalapsulated with a css-class, define its name here
	"show_replies"		=> 1,
		# if there are already replys, a link will be added telling about the replys
		# and where to comment
	"replies_notice"	=> "<p class=\"replies\">There are already #replies.totalItems# replies at G+. <a href=\"#url#\">Please follow the discussion there</a>.</p>",
	"show_source"		=> 1,
		# If a notice of the source will be displayed; This wont be displayed, if the current item
		# contains replies, which will also target the source.
	"source_notice"		=> "<p class=\"notice\">This article was <a href=\"#url#\">published at G+ first</a>.</p>",	
	"pubindex_file"		=> 'pubindex.store',
		# Storefile with all articles that was already send to the blog before



};
my $DEBUG = 0;
###############################################################################


my $data = get_activities();


if ($data->{'status'}==1) {
	my $artikel = make_list($data->{'data'}->{'items'});
	blogArticles($artikel);
} else {
	print STDERR "Could not get a datastream from userid $CONFIG->{'userid'}\n";
	if ($data->{'error'}) {
		print STDERR "Errormessage: $data->{'error'}\n";
	}	
}

exit;
###############################################################################
sub blogArticles {
	my $blogartikel = shift;
	my $index = getPubindex();
	my $key;
	foreach $key (keys %{$blogartikel}) {
		if (($index) && ($index->{$blogartikel->{$key}->{'guid'}})) {
			# Wurde bereits ans Blog gesendet
			print "Article \"$blogartikel->{$key}->{'title'}\"\n  already send at  $index->{$blogartikel->{$key}->{'guid'}}->{'send'} \n" if ($DEBUG);
		} else {
			sendArticle($blogartikel->{$key});
			$index->{$blogartikel->{$key}->{'guid'}}->{'send'} = localtime(time);
			$index->{$blogartikel->{$key}->{'guid'}}->{'title'} = $blogartikel->{$key}->{'title'};
		}
	}
	storePubindex($index);
}
###############################################################################
sub sendArticle {
	my $this = shift;

        utf8::encode($this->{'description'});
        utf8::encode($this->{'title'});

	if ($DEBUG) {
		print STDERR "Send to blog:\n";
		print STDERR "$this->{'title'}\n";
		print STDERR "guid: $this->{'guid'}\n";
	}

	my $xmlrpc = XMLRPC::Lite->proxy($CONFIG->{'url_blogxmlrpc'});
	my $call = $xmlrpc->call('metaWeblog.newPost',
		$CONFIG->{'blog_id'}, 
		$CONFIG->{'blog_username'},
		$CONFIG->{'blog_password'},
		{
			title => $this->{'title'},
			pubDate => $this->{'created'},
			description => $this->{'description'},
			category => $CONFIG->{'blog_defaultcategory'}
			
		},
		1);
	return;
}
###############################################################################
sub storePubindex {
	my $index = shift;
	return if (not $index);
	store($index,$CONFIG->{'pubindex_file'});
}
###############################################################################
sub getPubindex {
	my $result;
	 if (-r $CONFIG->{'pubindex_file'}) {
                $result = retrieve($CONFIG->{'pubindex_file'});
        }
	return $result;
}
###############################################################################
sub make_list {
	my $items = shift;
	my $i;
	my @list = @{$items};
	my $this;
	my $result;
	for ($i=0; $i<=$#list; $i++) {
		next if (($list[$i]->{'verb'} ne 'post') && ($CONFIG->{'onlyposts'}));
		$this = make_blogarticle($list[$i]);
		if ($this) {
			$result->{$this->{'guid'}} = $this;
		}
	}
	return $result;
}
###############################################################################
sub make_blogarticle {
	my $item = shift;
	return if (not $item);
	my $res;
	$res->{'guid'} = $item->{'url'};
	$res->{'created'} = $item->{'published'};
	$res->{'title'} = formattitle($item->{'title'});
	if (not $item->{'object'}->{'originalContent'}) {
		$item->{'object'}->{'originalContent'} = $item->{'object'}->{'content'};
	}
	if ((length($item->{'object'}->{'originalContent'}) < $CONFIG->{'article_minlength'}) && ($CONFIG->{'article_minlength'} > 0)) {
		print STDERR "Article too short\n" if ($DEBUG>2);
		return;
	} else {
	        $res->{'description'} = formatdesc($item->{'object'}->{'content'},$item->{'object'}->{'attachments'});
	}
	if (($CONFIG->{'show_replies'}) && ($item->{'object'}->{'replies'}->{'totalItems'} > 0)) {
		my $rn = $CONFIG->{'replies_notice'};	
		$rn =~ s/#replies.totalItems#/$item->{'object'}->{'replies'}->{'totalItems'}/gi;
		$rn =~ s/#url#/$item->{'url'}/gi;
		$res->{'description'}  .= $rn;
	} elsif (($CONFIG->{'show_source'}) && ($CONFIG->{'source_notice'})) {
		my $rn = $CONFIG->{'source_notice'};
                $rn =~ s/#url#/$item->{'url'}/gi;
                $res->{'description'}  .= $rn;
	}

	return $res;
}
sub formatdesc {
	my $text = shift;
	my $attachment = shift;
	my $res;
	if ((not $attachment)  || (not $CONFIG->{'show_attachments'})) {
		if ($CONFIG->{'cssclass_articleborder'}) {
			$res = "<div class=\"$CONFIG->{'cssclass_articleborder'}\">\n";
		}
		if ($CONFIG->{'add_paragraph'}) {
			$res .= "<p>\n";
		}
		$res .= $text;
		if ($CONFIG->{'add_paragraph'}) {
                        $res .= "\n</p>\n";
                }
		if ($CONFIG->{'cssclass_articleborder'}) {
			$res .= "\n</div>\n";
		}
		return $text;
	} else {
		my @att = @{$attachment};
		my $l;
		my $atext = "";
		my $url;
		my $title;
		my $info;
		my $imgsrc;
		my $addclass = $CONFIG->{'cssclass_attachments'};

		if ((scalar(@att)==1) && ($att[0]->{'objectType'} eq 'article')) {
			# verlinkung mit Website; Ein Bild ist aber nicht vorhanden.
			$addclass .= " textlink";
			$atext .= "<a href=\"$att[0]->{'url'}\">$att[0]->{'displayName'}</a>";
			if ($CONFIG->{'show_attachment_linkcontent'}) {
                                $atext .= "<span class=\"$CONFIG->{'cssclass_linkcontent'}\">$att[0]->{'content'}</span>";
                        }
		} elsif ((scalar(@att)==1) && ($att[0]->{'objectType'} eq 'photo')) {
			$addclass .= " photo";
			# Keine Verlinkung: Aber ein Bild ist eingebaut
			$atext .= "<img src=\"$att[0]->{'fullImage'}->{'url'}\" alt=\"$att[0]->{'content'}\" />";	
		} elsif ((scalar(@att)==2) && 
			( (($att[0]->{'objectType'} eq 'article') && ($att[1]->{'objectType'} eq 'photo'))
		       || (($att[1]->{'objectType'} eq 'article') && ($att[0]->{'objectType'} eq 'photo')) ) ) {
			# Verlinkung mit anderer Webseite; Das eine Object ist die Verlinkung, das andere
			# Ein Bild von der verlinkten Website
			$addclass .= " photolink";
			if (($att[0]->{'objectType'} eq 'article') && ($att[1]->{'objectType'} eq 'photo')) {
				$imgsrc = $att[1]->{'fullImage'}->{'url'};
				$url = $att[0]->{'url'};
				$title = $att[0]->{'displayName'};
				$info = $att[0]->{'content'};
			} else {
				$imgsrc = $att[0]->{'fullImage'}->{'url'};
                                $url = $att[1]->{'url'};
                                $title = $att[1]->{'displayName'};
				$info = $att[1]->{'content'};
			}
			$atext .= "<a href=\"$url\"><img src=\"$imgsrc\" />$title</a>";
			if ($CONFIG->{'show_attachment_linkcontent'}) {
				$atext .= "<span class=\"$CONFIG->{'cssclass_linkcontent'}\">$info</span>";
			}
		} elsif ((scalar(@att)==2) && ($att[0]->{'objectType'} eq 'photo') && ($att[1]->{'objectType'} eq 'photo') ) {
			# Sonderfall: Noch kein Album, aber trotzdem 2 Bilder
			$addclass .= " photo";
				
			$atext .= "<img src=\"$att[0]->{'fullImage'}->{'url'}\" alt=\"$att[0]->{'content'}\" />";
			$atext .= "<img src=\"$att[1]->{'fullImage'}->{'url'}\" alt=\"$att[1]->{'content'}\" />";			
		} elsif ($att[0]->{'objectType'} eq 'photo-album') {
			$addclass .= " albumlink";
			$atext .= "<a href=\"$att[0]->{'url'}\">$att[0]->{'displayName'}</a>";
		} else {
			# undefined
			$atext = "";
		}
		if ($CONFIG->{'cssclass_articleborder'}) {
			$res = "<div class=\"$CONFIG->{'cssclass_articleborder'}\">\n";
		}
                if ($CONFIG->{'add_paragraph'}) {
                        $res .= "<p>\n";
                }
                $res .= $text;
                if ($CONFIG->{'add_paragraph'}) {
                        $res .= "\n</p>\n";
                }
		if ($CONFIG->{'cssclass_articleborder'}) {
                	$res .= "\n</div>\n";
		}
		 if ( $atext) {
                        $res .= "<div class=\"$addclass\">\n";
			$res .= $atext;
                        $res .= "</div>\n";
                }
		return $res;
	}

	return $text;
}
###################
sub formattitle {
	my $text = shift;
	$text =~ s/\((.*)$//gi;
	$text =~ s/[\.;:!]\s+(.*)//gi;
		
	return $text;
}
#################
sub get_activities {
	my $collection = shift || "public";
	my $res;

	my $url =  $CONFIG->{'url_googleapi'}.$CONFIG->{'uri_activitylist'}.$CONFIG->{'userid'}."/activities/".$collection;
	$url .= "?key=".$CONFIG->{'api_key'};


	if ($CONFIG->{'fieldfilter'}) {
		$url .= $CONFIG->{'fieldfilter'};
	}

	print STDERR "Get Stream from URL: $url\n" if ($DEBUG);
	my $ua = LWP::UserAgent->new;
 	my $response = $ua->get( $url);
 
 	if ($response->is_success) {
		$res->{'data'} = JSON->new->utf8(1)->decode($response->content);
		$res->{'status'} = 1;
 	} else {
		$res->{'error'} = $response->status_line;
		$res->{'status'} = -1;
 	}	
	return $res;
}

