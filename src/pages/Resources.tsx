"use client";

import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Pagination,
  PaginationContent,
  PaginationItem,
  PaginationLink,
  PaginationNext,
  PaginationPrevious,
} from "@/components/ui/pagination";
import { Textarea } from "@/components/ui/textarea";
import { useBookmarks } from "@/hooks/use-bookmarks";
import { usePagination } from "@/hooks/use-pagination";
import {
  Book,
  Bookmark,
  BookmarkCheck,
  Brain,
  Download,
  MessageSquare,
  Plus,
  Search
} from "lucide-react";
import type React from "react";
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Translate } from "../components/Translate";
import { supabase } from "../lib/supabase";
import { extractTextFromPdf } from "../utils/pdfExtractor";
import { generatePdfThumbnail } from "../utils/pdfThumbnail";

interface Resource {
  id: string;
  name: string;
  description: string;
  file_url: string;
  thumbnail_url: string | null;
  created_at: string;
  user_id: string;
}

const ITEMS_PER_PAGE = 6;

export default function Resources() {
  const navigate = useNavigate();

  // ---------------------------
  // State variables
  // ---------------------------
  const [resources, setResources] = useState<Resource[]>([]);
  const [filteredResources, setFilteredResources] = useState<Resource[]>([]);
  const [thumbnails, setThumbnails] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [isDialogOpen, setisDialogOpen] = useState<boolean>(false);

  const [searchQuery, setSearchQuery] = useState("");
  const [showBookmarked, setShowBookmarked] = useState(false);

  // Form data for uploading a new resource
  const [formData, setFormData] = useState({
    name: "",
    description: "",
    file: null as File | null,
    thumbnail: null as File | null,
  });

  // ---------------------------
  // Hooks for pagination/bookmarks
  // ---------------------------
  const {
    bookmarks,
    loading: bookmarksLoading,
    addBookmark,
    removeBookmark,
    isBookmarked,
  } = useBookmarks("resource");

  const {
    currentItems,
    currentPage,
    totalPages,
    nextPage,
    previousPage,
    goToPage,
  } = usePagination({
    items: filteredResources,
    itemsPerPage: ITEMS_PER_PAGE,
  });

  // ---------------------------
  // Effects
  // ---------------------------
  useEffect(() => {
    fetchResources();
  }, []);

  // Generate thumbnails if resource doesn't have a thumbnail_url
  // Runs whenever `resources` changes
  useEffect(() => {
    resources.forEach(async (resource) => {
      if (!resource.thumbnail_url && !thumbnails[resource.id]) {
        try {
          const thumbnail = await generatePdfThumbnail(resource.file_url);
          setThumbnails((prev) => ({
            ...prev,
            [resource.id]: thumbnail,
          }));
        } catch (error) {
          console.error("Error generating thumbnail:", error);
        }
      }
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resources]);

  // Filter resources by search or bookmarked status
  useEffect(() => {
    let filtered = resources;

    // Apply search filter
    if (searchQuery) {
      filtered = filtered.filter(
        (resource) =>
          resource.name.toLowerCase().includes(searchQuery.toLowerCase()) ||
          resource.description.toLowerCase().includes(searchQuery.toLowerCase())
      );
    }

    // Apply bookmarks filter
    if (showBookmarked) {
      filtered = filtered.filter((resource) => isBookmarked(resource.id));
    }

    setFilteredResources(filtered);
  }, [resources, searchQuery, showBookmarked, bookmarks, isBookmarked]);

  // ---------------------------
  // Supabase queries / uploads
  // ---------------------------
  const fetchResources = async () => {
    try {
      const { data, error } = await supabase
        .from("resources")
        .select("*")
        .order("created_at", { ascending: false });

      if (error) throw error;
      if (data) {
        setResources(data);
      }
    } catch (err) {
      console.error("Error fetching resources:", err);
    } finally {
      setLoading(false);
    }
  };

  const handleFileChange = (
    e: React.ChangeEvent<HTMLInputElement>,
    type: "file" | "thumbnail"
  ) => {
    const file = e.target.files?.[0];
    if (file) {
      if (type === "file" && !file.type.includes("pdf")) {
        alert("Only PDF files are allowed");
        return;
      }
      if (type === "thumbnail" && !file.type.includes("image")) {
        alert("Only image files are allowed for thumbnails");
        return;
      }
      setFormData({ ...formData, [type]: file });
    }
  };

  const uploadFile = async (file: File, path: string) => {
    const { error } = await supabase.storage
      .from("resources")
      .upload(path, file);

    if (error) throw error;

    // Get the public URL of the uploaded file
    const { data: urlData } = supabase.storage
      .from("resources")
      .getPublicUrl(path);

    if (!urlData) throw new Error("Could not retrieve file URL.");
    return urlData.publicUrl;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!formData.file) return; // must have a PDF

    try {
      setUploading(true);
      // Get currently logged-in user
      const {
        data: { user },
        error: userError,
      } = await supabase.auth.getUser();

      if (userError || !user) {
        throw new Error("No user found or error retrieving user");
      }

      // Upload the PDF file
      const fileUrl = await uploadFile(
        formData.file,
        `${user.id}/${Date.now()}-${formData.file.name}`
      );

      // Upload the thumbnail if provided
      let thumbnailUrl: string | null = null;
      if (formData.thumbnail) {
        thumbnailUrl = await uploadFile(
          formData.thumbnail,
          `${user.id}/thumbnails/${formData.thumbnail.name}`
        );
      }

      // Insert resource entry into DB
      const { error } = await supabase.from("resources").insert([
        {
          name: formData.name,
          description: formData.description,
          file_url: fileUrl,
          thumbnail_url: thumbnailUrl,
          user_id: user.id,
        },
      ]);

      if (error) throw error;

      setisDialogOpen(false);
      // Reset the form
      setFormData({
        name: "",
        description: "",
        file: null,
        thumbnail: null,
      });

      // Refresh resources list
      fetchResources();
    } catch (err) {
      console.error("Error uploading resource:", err);
      alert("Error uploading resource. Please try again.");
    } finally {
      setUploading(false);
    }
  };

  // ---------------------------
  // PDF actions (chat/quiz)
  // ---------------------------
  const handlePdfAction = async (
    resource: Resource,
    action: "chat" | "quiz"
  ) => {
    try {
      // Fetch the PDF as a blob
      const response = await fetch(resource.file_url);
      const blob = await response.blob();

      // Create a File object
      const file = new File([blob], resource.name, { type: "application/pdf" });

      // Extract text from the PDF
      const pdfText = await extractTextFromPdf(file);

      // Store content in sessionStorage for the chat/quiz pages
      sessionStorage.setItem("pdfContent", pdfText);
      sessionStorage.setItem("pdfName", resource.name);
      sessionStorage.setItem("pdfUrl", resource.file_url);

      navigate(action === "chat" ? "/pdf-chat" : "/quiz");
    } catch (error) {
      console.error("Error processing PDF:", error);
      alert("Error processing PDF. Please try again.");
    }
  };

  // ---------------------------
  // Bookmark toggling
  // ---------------------------
  const toggleBookmark = async (resourceId: string) => {
    if (isBookmarked(resourceId)) {
      await removeBookmark(resourceId);
    } else {
      await addBookmark(resourceId);
    }
  };

  // ---------------------------
  // Rendering
  // ---------------------------
  return (
    <div className="min-h-screen bg-background text-foreground py-12 px-4 sm:px-6 lg:px-8">
      <div className="max-w-7xl mx-auto">
        {/* Page Header with animated background */}
        <div className="relative py-16 px-4 sm:px-6 lg:px-8 mb-12 rounded-2xl overflow-hidden bg-gradient-to-br from-muted to-primary/10">
          {/* Animated grid background */}
          <div className="absolute inset-0 z-0">
            <div className="absolute inset-0 bg-[linear-gradient(to_right,hsl(var(--border))_1px,transparent_1px),linear-gradient(to_bottom,hsl(var(--border))_1px,transparent_1px)] bg-[size:14px_24px] [mask-image:radial-gradient(ellipse_60%_50%_at_50%_0%,#000_70%,transparent_100%)]" />
          </div>

          <div className="relative z-10 text-center">
            <Book className="mx-auto h-16 w-16 text-primary" />
            <h2 className="mt-2 text-4xl font-bold bg-clip-text text-transparent bg-gradient-to-r from-primary via-accent-foreground to-primary">
              <Translate>Learning Resources</Translate>
            </h2>
            <p className="mt-2 text-xl text-muted-foreground max-w-2xl mx-auto">
              <Translate>
                Explore and share educational materials to enhance your learning
                journey
              </Translate>
            </p>
          </div>
        </div>

        {/* Search, Bookmarks, and Upload Button */}
        <div className="mb-8 flex flex-col sm:flex-row justify-between items-center gap-4">
          <div className="relative w-full sm:w-auto flex-1 max-w-md">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Search className="h-5 w-5 text-muted-foreground" />
            </div>
            <Input
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Search resources..."
              className="pl-10 bg-input border-border text-foreground placeholder:text-muted-foreground focus:ring-primary focus:border-primary"
            />
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 w-full sm:w-auto">
            <Button
              variant={showBookmarked ? "default" : "outline"}
              onClick={() => setShowBookmarked(!showBookmarked)}
              className={
                showBookmarked
                  ? "bg-primary hover:bg-primary/90 text-primary-foreground"
                  : "border-primary text-primary hover:bg-primary/10"
              }
            >
              {showBookmarked ? (
                <BookmarkCheck className="h-4 w-4 mr-2" />
              ) : (
                <Bookmark className="h-4 w-4 mr-2" />
              )}
              {showBookmarked ? "Show All" : "Show Bookmarked"}
            </Button>

            {/* Dialog for uploading a new resource */}
            <Dialog open={isDialogOpen} onOpenChange={setisDialogOpen}>
              <DialogTrigger asChild>
                <Button
                  className="bg-primary hover:bg-primary/90 text-primary-foreground"
                  onClick={() => {
                    setisDialogOpen(true);
                  }}
                >
                  <Plus className="h-4 w-4 mr-2" />
                  <Translate>Upload PDF</Translate>
                </Button>
              </DialogTrigger>
              <DialogContent className="bg-card border-border text-card-foreground">
                <DialogHeader>
                  <DialogTitle className="text-card-foreground">
                    <Translate>Upload New Resource</Translate>
                  </DialogTitle>
                  <DialogDescription className="text-muted-foreground">
                    <Translate>Provide details and upload your PDF resource.</Translate>
                  </DialogDescription>
                </DialogHeader>
                <form onSubmit={handleSubmit} className="space-y-4">
                  <div>
                    <Label htmlFor="name" className="text-muted-foreground">
                      <Translate>Title</Translate>
                    </Label>
                    <Input
                      id="name"
                      required
                      value={formData.name}
                      onChange={(e) =>
                        setFormData({ ...formData, name: e.target.value })
                      }
                      className="bg-input border-border text-foreground"
                    />
                  </div>
                  <div>
                    <Label htmlFor="description" className="text-muted-foreground">
                      <Translate>Description</Translate>
                    </Label>
                    <Textarea
                      id="description"
                      required
                      value={formData.description}
                      onChange={(e) =>
                        setFormData({
                          ...formData,
                          description: e.target.value,
                        })
                      }
                      rows={3}
                      className="bg-input border-border text-foreground"
                    />
                  </div>
                  <div>
                    <Label htmlFor="file" className="text-muted-foreground">
                      PDF File
                    </Label>
                    <Input
                      id="file"
                      type="file"
                      accept=".pdf"
                      required
                      onChange={(e) => handleFileChange(e, "file")}
                      className="bg-input border-border text-foreground"
                    />
                  </div>
                  <div>
                    <Label htmlFor="thumbnail" className="text-muted-foreground">
                      Thumbnail (optional)
                    </Label>
                    <Input
                      id="thumbnail"
                      type="file"
                      accept="image/*"
                      onChange={(e) => handleFileChange(e, "thumbnail")}
                      className="bg-input border-border text-foreground"
                    />
                  </div>
                  <Button
                    type="submit"
                    disabled={uploading}
                    className="w-full bg-primary hover:bg-primary/90 text-primary-foreground"
                  >
                    {uploading ? "Uploading..." : <Translate>Upload</Translate>}
                  </Button>
                </form>
              </DialogContent>
            </Dialog>
          </div>
        </div>

        {/* Loading skeleton or content */}
        {loading || bookmarksLoading ? (
          // Show skeletons if loading
          <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
            {Array(6)
              .fill(0)
              .map((_, i) => (
                <Card key={i} className="animate-pulse bg-card border-border">
                  <CardHeader>
                    <div className="h-48 bg-muted rounded-md mb-4" />
                    <div className="h-6 bg-muted rounded w-3/4 mb-2" />
                    <div className="h-4 bg-muted rounded w-1/2" />
                  </CardHeader>
                  <CardContent>
                    <div className="space-y-2">
                      <div className="h-8 bg-muted rounded"></div>
                      <div className="h-8 bg-muted rounded"></div>
                    </div>
                  </CardContent>
                </Card>
              ))}
          </div>
        ) : filteredResources.length === 0 ? (
          // No resources found
          <Card className="text-center p-8 bg-card border-border">
            <CardContent>
              <Book className="mx-auto h-12 w-12 text-muted-foreground mb-4" />
              <p className="text-xl text-card-foreground">
                {showBookmarked
                  ? "No bookmarked resources found"
                  : "No resources found"}
              </p>
              <p className="mt-2 text-muted-foreground">
                {showBookmarked
                  ? "Bookmark some resources to see them here"
                  : "Try a different search term or upload a new resource"}
              </p>
            </CardContent>
          </Card>
        ) : (
          // Display paginated resources
          <>
            <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
              {currentItems.map((resource) => (
                <Card
                  key={resource.id}
                  className="bg-card/50 backdrop-blur-sm border-border hover:shadow-lg hover:ring-2 hover:ring-primary/20 transition-all duration-300"
                >
                  <CardHeader>
                    {/* Title and Bookmark icon */}
                    <div className="flex justify-between items-start">
                      <CardTitle className="text-card-foreground truncate pr-8">
                        {resource.name}
                      </CardTitle>
                      <Button
                        variant="ghost"
                        size="icon"
                        className="h-8 w-8 text-muted-foreground hover:text-primary hover:bg-muted"
                        onClick={() => toggleBookmark(resource.id)}
                      >
                        {isBookmarked(resource.id) ? (
                          <BookmarkCheck className="h-5 w-5 text-primary" />
                        ) : (
                          <Bookmark className="h-5 w-5" />
                        )}
                      </Button>
                    </div>

                    {/* Thumbnail or generated thumbnail */}
                    <div className="aspect-w-16 aspect-h-9 mb-4 mt-2">
                      {resource.thumbnail_url ? (
                        <img
                          src={resource.thumbnail_url || "/placeholder.svg"}
                          alt={resource.name}
                          className="w-full h-48 object-cover rounded-md"
                        />
                      ) : thumbnails[resource.id] ? (
                        <img
                          src={thumbnails[resource.id] || "/placeholder.svg"}
                          alt={resource.name}
                          className="w-full h-48 object-cover rounded-md"
                        />
                      ) : (
                        <div className="w-full h-48 bg-muted flex items-center justify-center rounded-md">
                          <Book className="h-12 w-12 text-muted-foreground" />
                        </div>
                      )}
                    </div>

                    <CardDescription className="text-muted-foreground">
                      {resource.description}
                    </CardDescription>
                  </CardHeader>

                  <CardContent>
                    <div className="flex flex-col space-y-2">
                      <div className="grid grid-cols-1 lg:grid-cols-2 gap-2">
                        <Button
                          onClick={() => handlePdfAction(resource, "chat")}
                          className="flex-1 bg-primary hover:bg-primary/90 text-primary-foreground"
                        >
                          <MessageSquare className="h-4 w-4 mr-2" />
                          <Translate>Chat with PDF</Translate>
                        </Button>
                        <Button
                          onClick={() => handlePdfAction(resource, "quiz")}
                          className="flex-1 bg-primary hover:bg-primary/90 text-primary-foreground"
                        >
                          <Brain className="h-4 w-4 mr-2" />
                          <Translate>Generate Quiz</Translate>
                        </Button>
                      </div>
                      <Button
                        variant="outline"
                        asChild
                        className="w-full border-border text-primary hover:bg-primary/10"
                      >
                        <a
                          href={resource.file_url}
                          target="_blank"
                          rel="noopener noreferrer"
                        >
                          <Download className="h-4 w-4 mr-2" />
                          <Translate>Download PDF</Translate>
                        </a>
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              ))}
            </div>

            {/* Pagination controls */}
            {totalPages > 1 && (
              <div className="mt-8 overflow-x-auto whitespace-nowrap">
                <Pagination className="inline-flex items-center gap-2">
                  <PaginationContent className="flex">
                    {/* Previous Button */}
                    <PaginationItem>
                      <PaginationPrevious
                        onClick={previousPage}
                        className="text-muted-foreground hover:text-foreground border-border hover:bg-muted"
                      />
                    </PaginationItem>

                    {/* Pages with Ellipsis */}
                    {(() => {
                      const pagesToShow = [];

                      if (totalPages <= 3) {
                        // If there are 3 or fewer pages, show them all directly
                        for (let i = 1; i <= totalPages; i++) {
                          pagesToShow.push(i);
                        }
                      } else {
                        // Always show first page
                        pagesToShow.push(1);

                        // If currentPage is greater than 2, we have a gap -> add ellipsis
                        if (currentPage > 2) {
                          pagesToShow.push("...");
                        }

                        // If current is neither the first nor the last, show it
                        if (currentPage > 1 && currentPage < totalPages) {
                          pagesToShow.push(currentPage);
                        }

                        // If currentPage is at least 2 less than totalPages, we have a gap -> add ellipsis
                        if (currentPage < totalPages - 1) {
                          pagesToShow.push("...");
                        }

                        // Always show last page (unless totalPages is 1, but we have the check above)
                        if (totalPages !== 1) {
                          pagesToShow.push(totalPages);
                        }
                      }

                      // Render pages or ellipses
                      return pagesToShow.map((page, index) => {
                        if (page === "...") {
                          // Render ellipses
                          return (
                            <PaginationItem key={`dots-${index}`} disabled>
                              <span className="px-2 text-muted-foreground">...</span>
                            </PaginationItem>
                          );
                        }
                        
                        return (
                          <PaginationItem key={page}>
                            <PaginationLink
                              onClick={() => goToPage(page)}
                              isActive={currentPage === page}
                              className={
                                currentPage === page
                                  ? "bg-primary text-primary-foreground border-primary"
                                  : "text-muted-foreground border-border hover:text-foreground hover:bg-muted"
                              }
                            >
                              {page}
                            </PaginationLink>
                          </PaginationItem>
                        );
                      });
                    })()}

                    {/* Next Button */}
                    <PaginationItem>
                      <PaginationNext
                        onClick={nextPage}
                        className="text-muted-foreground hover:text-foreground border-border hover:bg-muted"
                      />
                    </PaginationItem>
                  </PaginationContent>
                </Pagination>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
